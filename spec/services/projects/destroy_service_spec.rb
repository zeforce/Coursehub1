require 'spec_helper'

describe Projects::DestroyService, services: true do
  let!(:user) { create(:user) }
  let!(:project) { create(:project, namespace: user.namespace) }
  let!(:path) { project.repository.path_to_repo }
  let!(:remove_path) { path.sub(/\.git\Z/, "+#{project.id}+deleted.git") }

  context 'Sidekiq inline' do
    before do
      # Run sidekiq immediatly to check that renamed repository will be removed
      Sidekiq::Testing.inline! { destroy_project(project, user, {}) }
    end

    it { expect(Project.all).not_to include(project) }
    it { expect(Dir.exist?(path)).to be_falsey }
    it { expect(Dir.exist?(remove_path)).to be_falsey }
  end

  context 'Sidekiq fake' do
    before do
      # Dont run sidekiq to check if renamed repository exists
      Sidekiq::Testing.fake! { destroy_project(project, user, {}) }
    end

    it { expect(Project.all).not_to include(project) }
    it { expect(Dir.exist?(path)).to be_falsey }
    it { expect(Dir.exist?(remove_path)).to be_truthy }
  end

  context 'container registry' do
    before do
      stub_container_registry_config(enabled: true)
      stub_container_registry_tags('tag')
    end

    context 'tags deletion succeeds' do
      it do
        expect_any_instance_of(ContainerRegistry::Tag).to receive(:delete).and_return(true)

        destroy_project(project, user, {})
      end
    end

    context 'tags deletion fails' do
      before { expect_any_instance_of(ContainerRegistry::Tag).to receive(:delete).and_return(false) }

      subject { destroy_project(project, user, {}) }

      it { expect{subject}.to raise_error(Projects::DestroyService::DestroyError) }
    end
  end

  def destroy_project(project, user, params)
    Projects::DestroyService.new(project, user, params).execute
  end
end
