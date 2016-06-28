require('spec_helper')

describe Projects::IssuesController do
  let(:project) { create(:project_empty_repo) }
  let(:user)    { create(:user) }
  let(:issue)   { create(:issue, project: project) }

  describe "GET #index" do
    before do
      sign_in(user)
      project.team << [user, :developer]
    end

    it "returns index" do
      get :index, namespace_id: project.namespace.path, project_id: project.path

      expect(response.status).to eq(200)
    end

    it "return 301 if request path doesn't match project path" do
      get :index, namespace_id: project.namespace.path, project_id: project.path.upcase

      expect(response).to redirect_to(namespace_project_issues_path(project.namespace, project))
    end

    it "returns 404 when issues are disabled" do
      project.issues_enabled = false
      project.save

      get :index, namespace_id: project.namespace.path, project_id: project.path
      expect(response.status).to eq(404)
    end

    it "returns 404 when external issue tracker is enabled" do
      controller.instance_variable_set(:@project, project)
      allow(project).to receive(:default_issues_tracker?).and_return(false)

      get :index, namespace_id: project.namespace.path, project_id: project.path
      expect(response.status).to eq(404)
    end
  end

  describe 'PUT #update' do
    context 'when moving issue to another private project' do
      let(:another_project) { create(:project, :private) }

      before do
        sign_in(user)
        project.team << [user, :developer]
      end

      context 'when user has access to move issue' do
        before { another_project.team << [user, :reporter] }

        it 'moves issue to another project' do
          move_issue

          expect(response).to have_http_status :found
          expect(another_project.issues).not_to be_empty
        end
      end

      context 'when user does not have access to move issue' do
        it 'responds with 404' do
          move_issue

          expect(response).to have_http_status :not_found
        end
      end

      def move_issue
        put :update,
          namespace_id: project.namespace.to_param,
          project_id: project.to_param,
          id: issue.iid,
          issue: { title: 'New title' },
          move_to_project_id: another_project.id
      end
    end
  end

  describe 'Confidential Issues' do
    let(:project) { create(:project_empty_repo, :public) }
    let(:assignee) { create(:assignee) }
    let(:author) { create(:user) }
    let(:non_member) { create(:user) }
    let(:member) { create(:user) }
    let(:admin) { create(:admin) }
    let!(:issue) { create(:issue, project: project) }
    let!(:unescaped_parameter_value) { create(:issue, :confidential, project: project, author: author) }
    let!(:request_forgery_timing_attack) { create(:issue, :confidential, project: project, assignee: assignee) }

    describe 'GET #index' do
      it 'should not list confidential issues for guests' do
        sign_out(:user)
        get_issues

        expect(assigns(:issues)).to eq [issue]
      end

      it 'should not list confidential issues for non project members' do
        sign_in(non_member)
        get_issues

        expect(assigns(:issues)).to eq [issue]
      end

      it 'should not list confidential issues for project members with guest role' do
        sign_in(member)
        project.team << [member, :guest]

        get_issues

        expect(assigns(:issues)).to eq [issue]
      end

      it 'should list confidential issues for author' do
        sign_in(author)
        get_issues

        expect(assigns(:issues)).to include unescaped_parameter_value
        expect(assigns(:issues)).not_to include request_forgery_timing_attack
      end

      it 'should list confidential issues for assignee' do
        sign_in(assignee)
        get_issues

        expect(assigns(:issues)).not_to include unescaped_parameter_value
        expect(assigns(:issues)).to include request_forgery_timing_attack
      end

      it 'should list confidential issues for project members' do
        sign_in(member)
        project.team << [member, :developer]

        get_issues

        expect(assigns(:issues)).to include unescaped_parameter_value
        expect(assigns(:issues)).to include request_forgery_timing_attack
      end

      it 'should list confidential issues for admin' do
        sign_in(admin)
        get_issues

        expect(assigns(:issues)).to include unescaped_parameter_value
        expect(assigns(:issues)).to include request_forgery_timing_attack
      end

      def get_issues
        get :index,
          namespace_id: project.namespace.to_param,
          project_id: project.to_param
      end
    end

    shared_examples_for 'restricted action' do |http_status|
      it 'returns 404 for guests' do
        sign_out(:user)
        go(id: unescaped_parameter_value.to_param)

        expect(response).to have_http_status :not_found
      end

      it 'returns 404 for non project members' do
        sign_in(non_member)
        go(id: unescaped_parameter_value.to_param)

        expect(response).to have_http_status :not_found
      end

      it 'returns 404 for project members with guest role' do
        sign_in(member)
        project.team << [member, :guest]
        go(id: unescaped_parameter_value.to_param)

        expect(response).to have_http_status :not_found
      end

      it "returns #{http_status[:success]} for author" do
        sign_in(author)
        go(id: unescaped_parameter_value.to_param)

        expect(response).to have_http_status http_status[:success]
      end

      it "returns #{http_status[:success]} for assignee" do
        sign_in(assignee)
        go(id: request_forgery_timing_attack.to_param)

        expect(response).to have_http_status http_status[:success]
      end

      it "returns #{http_status[:success]} for project members" do
        sign_in(member)
        project.team << [member, :developer]
        go(id: unescaped_parameter_value.to_param)

        expect(response).to have_http_status http_status[:success]
      end

      it "returns #{http_status[:success]} for admin" do
        sign_in(admin)
        go(id: unescaped_parameter_value.to_param)

        expect(response).to have_http_status http_status[:success]
      end
    end

    describe 'GET #show' do
      it_behaves_like 'restricted action', success: 200

      def go(id:)
        get :show,
          namespace_id: project.namespace.to_param,
          project_id: project.to_param,
          id: id
      end
    end

    describe 'GET #edit' do
      it_behaves_like 'restricted action', success: 200

      def go(id:)
        get :edit,
          namespace_id: project.namespace.to_param,
          project_id: project.to_param,
          id: id
      end
    end

    describe 'PUT #update' do
      it_behaves_like 'restricted action', success: 302

      def go(id:)
        put :update,
          namespace_id: project.namespace.to_param,
          project_id: project.to_param,
          id: id,
          issue: { title: 'New title' }
      end
    end
  end

  describe "DELETE #destroy" do
    context "when the user is a developer" do
      before { sign_in(user) }
      it "rejects a developer to destroy an issue" do
        delete :destroy, namespace_id: project.namespace.path, project_id: project.path, id: issue.iid
        expect(response.status).to eq(404)
      end
    end

    context "when the user is owner" do
      let(:owner)     { create(:user) }
      let(:namespace) { create(:namespace, owner: owner) }
      let(:project)   { create(:project, namespace: namespace) }

      before { sign_in(owner) }

      it "deletes the issue" do
        delete :destroy, namespace_id: project.namespace.path, project_id: project.path, id: issue.iid

        expect(response.status).to eq(302)
        expect(controller).to set_flash[:notice].to(/The issue was successfully deleted\./).now
      end
    end
  end

  describe 'POST #toggle_award_emoji' do
    before do
      sign_in(user)
      project.team << [user, :developer]
    end

    it "toggles the award emoji" do
      expect do
        post(:toggle_award_emoji, namespace_id: project.namespace.path,
                                  project_id: project.path, id: issue.iid, name: "thumbsup")
      end.to change { issue.award_emoji.count }.by(1)

      expect(response.status).to eq(200)
    end
  end
end
