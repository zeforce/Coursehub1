require('spec_helper')

describe ProjectsController do
  let(:project) { create(:project) }
  let(:public_project) { create(:project, :public) }
  let(:user)    { create(:user) }
  let(:jpg)     { fixture_file_upload(Rails.root + 'spec/fixtures/rails_sample.jpg', 'image/jpg') }
  let(:txt)     { fixture_file_upload(Rails.root + 'spec/fixtures/doc_sample.txt', 'text/plain') }

  describe "GET show" do
    context "user not project member" do
      before { sign_in(user) }

      context "user does not have access to project" do
        let(:private_project) { create(:project, :private) }

        it "does not initialize notification setting" do
          get :show, namespace_id: private_project.namespace.path, id: private_project.path
          expect(assigns(:notification_setting)).to be_nil
        end
      end

      context "user has access to project" do
        context "and does not have notification setting" do
          it "initializes notification as disabled" do
            get :show, namespace_id: public_project.namespace.path, id: public_project.path
            expect(assigns(:notification_setting).level).to eq("global")
          end
        end

        context "and has notification setting" do
          before do
            setting = user.notification_settings_for(public_project)
            setting.level = :watch
            setting.save
          end

          it "shows current notification setting" do
            get :show, namespace_id: public_project.namespace.path, id: public_project.path
            expect(assigns(:notification_setting).level).to eq("watch")
          end
        end
      end
    end

    context "rendering default project view" do
      render_views

      it "renders the activity view" do
        allow(controller).to receive(:current_user).and_return(user)
        allow(user).to receive(:project_view).and_return('activity')

        get :show, namespace_id: public_project.namespace.path, id: public_project.path
        expect(response).to render_template('_activity')
      end

      it "renders the readme view" do
        allow(controller).to receive(:current_user).and_return(user)
        allow(user).to receive(:project_view).and_return('readme')

        get :show, namespace_id: public_project.namespace.path, id: public_project.path
        expect(response).to render_template('_readme')
      end

      it "renders the files view" do
        allow(controller).to receive(:current_user).and_return(user)
        allow(user).to receive(:project_view).and_return('files')

        get :show, namespace_id: public_project.namespace.path, id: public_project.path
        expect(response).to render_template('_files')
      end
    end

    context "when requested with case sensitive namespace and project path" do
      context "when there is a match with the same casing" do
        it "loads the project" do
          get :show, namespace_id: public_project.namespace.path, id: public_project.path

          expect(assigns(:project)).to eq(public_project)
          expect(response.status).to eq(200)
        end
      end

      context "when there is a match with different casing" do
        it "redirects to the normalized path" do
          get :show, namespace_id: public_project.namespace.path, id: public_project.path.upcase

          expect(assigns(:project)).to eq(public_project)
          expect(response).to redirect_to("/#{public_project.path_with_namespace}")
        end


        # MySQL queries are case insensitive by default, so this spec would fail.
        if Gitlab::Database.postgresql?
          context "when there is also a match with the same casing" do

            let!(:other_project) { create(:project, :public, namespace: public_project.namespace, path: public_project.path.upcase) }

            it "loads the exactly matched project" do

              get :show, namespace_id: public_project.namespace.path, id: public_project.path.upcase

              expect(assigns(:project)).to eq(other_project)
              expect(response.status).to eq(200)
            end
          end
        end
      end
    end

    context "when the url contains .atom" do
      let(:public_project_with_dot_atom) { build(:project, :public, name: 'my.atom', path: 'my.atom') }

      it 'expect an error creating the project' do
        expect(public_project_with_dot_atom).not_to be_valid
      end
    end

    context 'when the project is pending deletions' do
      it 'renders a 404 error' do
        project = create(:project, pending_delete: true)
        sign_in(user)

        get :show, namespace_id: project.namespace.path, id: project.path

        expect(response.status).to eq 404
      end
    end
  end

  describe "#update" do
    render_views

    let(:admin) { create(:admin) }

    it "sets the repository to the right path after a rename" do
      new_path = 'renamed_path'
      project_params = { path: new_path }
      controller.instance_variable_set(:@project, project)
      sign_in(admin)

      put :update,
          namespace_id: project.namespace.to_param,
          id: project.id,
          project: project_params

      expect(project.repository.path).to include(new_path)
      expect(assigns(:repository).path).to eq(project.repository.path)
      expect(response.status).to eq(200)
    end
  end

  describe "#destroy" do
    let(:admin) { create(:admin) }

    it "redirects to the dashboard" do
      controller.instance_variable_set(:@project, project)
      sign_in(admin)

      orig_id = project.id
      delete :destroy, namespace_id: project.namespace.path, id: project.path

      expect { Project.find(orig_id) }.to raise_error(ActiveRecord::RecordNotFound)
      expect(response.status).to eq(302)
      expect(response).to redirect_to(dashboard_projects_path)
    end
  end

  describe "POST #toggle_star" do
    it "toggles star if user is signed in" do
      sign_in(user)
      expect(user.starred?(public_project)).to be_falsey
      post(:toggle_star,
           namespace_id: public_project.namespace.to_param,
           id: public_project.to_param)
      expect(user.starred?(public_project)).to be_truthy
      post(:toggle_star,
           namespace_id: public_project.namespace.to_param,
           id: public_project.to_param)
      expect(user.starred?(public_project)).to be_falsey
    end

    it "does nothing if user is not signed in" do
      post(:toggle_star,
           namespace_id: project.namespace.to_param,
           id: public_project.to_param)
      expect(user.starred?(public_project)).to be_falsey
      post(:toggle_star,
           namespace_id: project.namespace.to_param,
           id: public_project.to_param)
      expect(user.starred?(public_project)).to be_falsey
    end
  end

  describe "DELETE remove_fork" do
    context 'when signed in' do
      before do
        sign_in(user)
      end

      context 'with forked project' do
        let(:project_fork) { create(:project, namespace: user.namespace) }

        before do
          create(:forked_project_link, forked_to_project: project_fork)
        end

        it 'should remove fork from project' do
          delete(:remove_fork,
              namespace_id: project_fork.namespace.to_param,
              id: project_fork.to_param, format: :js)

          expect(project_fork.forked?).to be_falsey
          expect(flash[:notice]).to eq('The fork relationship has been removed.')
          expect(response).to render_template(:remove_fork)
        end
      end

      context 'when project not forked' do
        let(:unforked_project) { create(:project, namespace: user.namespace) }

        it 'should do nothing if project was not forked' do
          delete(:remove_fork,
              namespace_id: unforked_project.namespace.to_param,
              id: unforked_project.to_param, format: :js)

          expect(flash[:notice]).to be_nil
          expect(response).to render_template(:remove_fork)
        end
      end
    end

    it "does nothing if user is not signed in" do
      delete(:remove_fork,
          namespace_id: project.namespace.to_param,
          id: project.to_param, format: :js)
      expect(response.status).to eq(401)
    end
  end

  describe "GET refs" do
    it "should get a list of branches and tags" do
      get :refs, namespace_id: public_project.namespace.path, id: public_project.path

      parsed_body = JSON.parse(response.body)
      expect(parsed_body["Branches"]).to include("master")
      expect(parsed_body["Tags"]).to include("v1.0.0")
      expect(parsed_body["Commits"]).to be_nil
    end

    it "should get a list of branches, tags and commits" do
      get :refs, namespace_id: public_project.namespace.path, id: public_project.path, ref: "123456"

      parsed_body = JSON.parse(response.body)
      expect(parsed_body["Branches"]).to include("master")
      expect(parsed_body["Tags"]).to include("v1.0.0")
      expect(parsed_body["Commits"]).to include("123456")
    end
  end
end
