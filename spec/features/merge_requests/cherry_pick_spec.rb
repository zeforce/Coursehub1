require 'spec_helper'

describe 'Cherry-pick Merge Requests' do
  let(:user) { create(:user) }
  let(:project) { create(:project) }
  let(:merge_request) { create(:merge_request_with_diffs, source_project: project, author: user) }

  before do
    login_as user
    project.team << [user, :master]
  end

  context "Viewing a merged merge request" do
    before do
      service = MergeRequests::MergeService.new(project, user)

      perform_enqueued_jobs do
        service.execute(merge_request)
      end
    end

    # Fast-forward merge, or merged before GitLab 8.5.
    context "Without a merge commit" do
      before do
        merge_request.merge_commit_sha = nil
        merge_request.save
      end

      it "doesn't show a Cherry-pick button" do
        visit namespace_project_merge_request_path(project.namespace, project, merge_request)

        expect(page).not_to have_link "Cherry-pick"
      end
    end

    context "With a merge commit" do
      it "shows a Cherry-pick button" do
        visit namespace_project_merge_request_path(project.namespace, project, merge_request)

        expect(page).to have_link "Cherry-pick"
      end
    end
  end
end
