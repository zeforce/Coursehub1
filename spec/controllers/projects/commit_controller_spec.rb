require 'rails_helper'

describe Projects::CommitController do
  describe 'GET show' do
    render_views

    let(:project) { create(:project) }

    before do
      user = create(:user)
      project.team << [user, :master]

      sign_in(user)
    end

    context 'with valid id' do
      it 'responds with 200' do
        go id: project.commit.id

        expect(response).to be_ok
      end
    end

    context 'with invalid id' do
      it 'responds with 404' do
        go id: project.commit.id.reverse

        expect(response).to be_not_found
      end
    end

    it 'handles binary files' do
      get(:show,
          namespace_id: project.namespace.to_param,
          project_id: project.to_param,
          id: TestEnv::BRANCH_SHA['binary-encoding'],
          format: "html")

      expect(response).to be_success
    end

    def go(id:)
      get :show,
        namespace_id: project.namespace.to_param,
        project_id: project.to_param,
        id: id
    end
  end
end
