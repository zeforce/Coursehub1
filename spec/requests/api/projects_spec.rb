# -*- coding: utf-8 -*-
require 'spec_helper'

describe API::API, api: true  do
  include ApiHelpers
  include Gitlab::CurrentSettings
  let(:user) { create(:user) }
  let(:user2) { create(:user) }
  let(:user3) { create(:user) }
  let(:admin) { create(:admin) }
  let(:project) { create(:project, creator_id: user.id, namespace: user.namespace) }
  let(:project2) { create(:project, path: 'project2', creator_id: user.id, namespace: user.namespace) }
  let(:snippet) { create(:project_snippet, :public, author: user, project: project, title: 'example') }
  let(:project_member) { create(:project_member, :master, user: user, project: project) }
  let(:project_member2) { create(:project_member, :developer, user: user3, project: project) }
  let(:user4) { create(:user) }
  let(:project3) do
    create(:project,
    :private,
    name: 'second_project',
    path: 'second_project',
    creator_id: user.id,
    namespace: user.namespace,
    merge_requests_enabled: false,
    issues_enabled: false, wiki_enabled: false,
    snippets_enabled: false)
  end
  let(:project_member3) do
    create(:project_member,
    user: user4,
    project: project3,
    access_level: ProjectMember::MASTER)
  end
  let(:project4) do
    create(:project,
    name: 'third_project',
    path: 'third_project',
    creator_id: user4.id,
    namespace: user4.namespace)
  end

  describe 'GET /projects' do
    before { project }

    context 'when unauthenticated' do
      it 'should return authentication error' do
        get api('/projects')
        expect(response.status).to eq(401)
      end
    end

    context 'when authenticated' do
      it 'should return an array of projects' do
        get api('/projects', user)
        expect(response.status).to eq(200)
        expect(json_response).to be_an Array
        expect(json_response.first['name']).to eq(project.name)
        expect(json_response.first['owner']['username']).to eq(user.username)
      end

      it 'should include the project labels as the tag_list' do
        get api('/projects', user)
        expect(response.status).to eq 200
        expect(json_response).to be_an Array
        expect(json_response.first.keys).to include('tag_list')
      end

      it 'should include open_issues_count' do
        get api('/projects', user)
        expect(response.status).to eq 200
        expect(json_response).to be_an Array
        expect(json_response.first.keys).to include('open_issues_count')
      end

      it 'should not include open_issues_count' do
        project.update_attributes( { issues_enabled: false } )

        get api('/projects', user)
        expect(response.status).to eq 200
        expect(json_response).to be_an Array
        expect(json_response.first.keys).not_to include('open_issues_count')
      end

      context 'and using search' do
        it 'should return searched project' do
          get api('/projects', user), { search: project.name }
          expect(response.status).to eq(200)
          expect(json_response).to be_an Array
          expect(json_response.length).to eq(1)
        end
      end

      context 'and using the visibility filter' do
        it 'should filter based on private visibility param' do
          get api('/projects', user), { visibility: 'private' }
          expect(response.status).to eq(200)
          expect(json_response).to be_an Array
          expect(json_response.length).to eq(user.namespace.projects.where(visibility_level: Gitlab::VisibilityLevel::PRIVATE).count)
        end

        it 'should filter based on internal visibility param' do
          get api('/projects', user), { visibility: 'internal' }
          expect(response.status).to eq(200)
          expect(json_response).to be_an Array
          expect(json_response.length).to eq(user.namespace.projects.where(visibility_level: Gitlab::VisibilityLevel::INTERNAL).count)
        end

        it 'should filter based on public visibility param' do
          get api('/projects', user), { visibility: 'public' }
          expect(response.status).to eq(200)
          expect(json_response).to be_an Array
          expect(json_response.length).to eq(user.namespace.projects.where(visibility_level: Gitlab::VisibilityLevel::PUBLIC).count)
        end
      end

      context 'and using sorting' do
        before do
          project2
          project3
        end

        it 'should return the correct order when sorted by id' do
          get api('/projects', user), { order_by: 'id', sort: 'desc' }
          expect(response.status).to eq(200)
          expect(json_response).to be_an Array
          expect(json_response.first['id']).to eq(project3.id)
        end
      end
    end
  end

  describe 'GET /projects/all' do
    before { project }

    context 'when unauthenticated' do
      it 'should return authentication error' do
        get api('/projects/all')
        expect(response.status).to eq(401)
      end
    end

    context 'when authenticated as regular user' do
      it 'should return authentication error' do
        get api('/projects/all', user)
        expect(response.status).to eq(403)
      end
    end

    context 'when authenticated as admin' do
      it 'should return an array of all projects' do
        get api('/projects/all', admin)
        expect(response.status).to eq(200)
        expect(json_response).to be_an Array

        expect(json_response).to satisfy do |response|
          response.one? do |entry|
            entry.has_key?('permissions') &&
            entry['name'] == project.name &&
              entry['owner']['username'] == user.username
          end
        end
      end
    end
  end

  describe 'GET /projects/starred' do
    let(:public_project) { create(:project, :public) }

    before do
      project_member2
      user3.update_attributes(starred_projects: [project, project2, project3, public_project])
    end

    it 'should return the starred projects viewable by the user' do
      get api('/projects/starred', user3)
      expect(response.status).to eq(200)
      expect(json_response).to be_an Array
      expect(json_response.map { |project| project['id'] }).to contain_exactly(project.id, public_project.id)
    end
  end

  describe 'POST /projects' do
    context 'maximum number of projects reached' do
      it 'should not create new project and respond with 403' do
        allow_any_instance_of(User).to receive(:projects_limit_left).and_return(0)
        expect { post api('/projects', user2), name: 'foo' }.
          to change {Project.count}.by(0)
        expect(response.status).to eq(403)
      end
    end

    it 'should create new project without path and return 201' do
      expect { post api('/projects', user), name: 'foo' }.
        to change { Project.count }.by(1)
      expect(response.status).to eq(201)
    end

    it 'should create last project before reaching project limit' do
      allow_any_instance_of(User).to receive(:projects_limit_left).and_return(1)
      post api('/projects', user2), name: 'foo'
      expect(response.status).to eq(201)
    end

    it 'should not create new project without name and return 400' do
      expect { post api('/projects', user) }.not_to change { Project.count }
      expect(response.status).to eq(400)
    end

    it "should assign attributes to project" do
      project = attributes_for(:project, {
        path: 'camelCasePath',
        description: FFaker::Lorem.sentence,
        issues_enabled: false,
        merge_requests_enabled: false,
        wiki_enabled: false
      })

      post api('/projects', user), project

      project.each_pair do |k,v|
        expect(json_response[k.to_s]).to eq(v)
      end
    end

    it 'should set a project as public' do
      project = attributes_for(:project, :public)
      post api('/projects', user), project
      expect(json_response['public']).to be_truthy
      expect(json_response['visibility_level']).to eq(Gitlab::VisibilityLevel::PUBLIC)
    end

    it 'should set a project as public using :public' do
      project = attributes_for(:project, { public: true })
      post api('/projects', user), project
      expect(json_response['public']).to be_truthy
      expect(json_response['visibility_level']).to eq(Gitlab::VisibilityLevel::PUBLIC)
    end

    it 'should set a project as internal' do
      project = attributes_for(:project, :internal)
      post api('/projects', user), project
      expect(json_response['public']).to be_falsey
      expect(json_response['visibility_level']).to eq(Gitlab::VisibilityLevel::INTERNAL)
    end

    it 'should set a project as internal overriding :public' do
      project = attributes_for(:project, :internal, { public: true })
      post api('/projects', user), project
      expect(json_response['public']).to be_falsey
      expect(json_response['visibility_level']).to eq(Gitlab::VisibilityLevel::INTERNAL)
    end

    it 'should set a project as private' do
      project = attributes_for(:project, :private)
      post api('/projects', user), project
      expect(json_response['public']).to be_falsey
      expect(json_response['visibility_level']).to eq(Gitlab::VisibilityLevel::PRIVATE)
    end

    it 'should set a project as private using :public' do
      project = attributes_for(:project, { public: false })
      post api('/projects', user), project
      expect(json_response['public']).to be_falsey
      expect(json_response['visibility_level']).to eq(Gitlab::VisibilityLevel::PRIVATE)
    end

    context 'when a visibility level is restricted' do
      before do
        @project = attributes_for(:project, { public: true })
        stub_application_setting(restricted_visibility_levels: [Gitlab::VisibilityLevel::PUBLIC])
      end

      it 'should not allow a non-admin to use a restricted visibility level' do
        post api('/projects', user), @project

        expect(response.status).to eq(400)
        expect(json_response['message']['visibility_level'].first).to(
          match('restricted by your GitLab administrator')
        )
      end

      it 'should allow an admin to override restricted visibility settings' do
        post api('/projects', admin), @project
        expect(json_response['public']).to be_truthy
        expect(json_response['visibility_level']).to(
          eq(Gitlab::VisibilityLevel::PUBLIC)
        )
      end
    end
  end

  describe 'POST /projects/user/:id' do
    before { project }
    before { admin }

    it 'should create new project without path and return 201' do
      expect { post api("/projects/user/#{user.id}", admin), name: 'foo' }.to change {Project.count}.by(1)
      expect(response.status).to eq(201)
    end

    it 'should respond with 400 on failure and not project' do
      expect { post api("/projects/user/#{user.id}", admin) }.
        not_to change { Project.count }

      expect(response.status).to eq(400)
      expect(json_response['message']['name']).to eq([
        'can\'t be blank',
        'is too short (minimum is 0 characters)',
        Gitlab::Regex.project_name_regex_message
      ])
      expect(json_response['message']['path']).to eq([
        'can\'t be blank',
        'is too short (minimum is 0 characters)',
        Gitlab::Regex.send(:project_path_regex_message)
      ])
    end

    it 'should assign attributes to project' do
      project = attributes_for(:project, {
        description: FFaker::Lorem.sentence,
        issues_enabled: false,
        merge_requests_enabled: false,
        wiki_enabled: false
      })

      post api("/projects/user/#{user.id}", admin), project

      project.each_pair do |k,v|
        next if k == :path
        expect(json_response[k.to_s]).to eq(v)
      end
    end

    it 'should set a project as public' do
      project = attributes_for(:project, :public)
      post api("/projects/user/#{user.id}", admin), project
      expect(json_response['public']).to be_truthy
      expect(json_response['visibility_level']).to eq(Gitlab::VisibilityLevel::PUBLIC)
    end

    it 'should set a project as public using :public' do
      project = attributes_for(:project, { public: true })
      post api("/projects/user/#{user.id}", admin), project
      expect(json_response['public']).to be_truthy
      expect(json_response['visibility_level']).to eq(Gitlab::VisibilityLevel::PUBLIC)
    end

    it 'should set a project as internal' do
      project = attributes_for(:project, :internal)
      post api("/projects/user/#{user.id}", admin), project
      expect(json_response['public']).to be_falsey
      expect(json_response['visibility_level']).to eq(Gitlab::VisibilityLevel::INTERNAL)
    end

    it 'should set a project as internal overriding :public' do
      project = attributes_for(:project, :internal, { public: true })
      post api("/projects/user/#{user.id}", admin), project
      expect(json_response['public']).to be_falsey
      expect(json_response['visibility_level']).to eq(Gitlab::VisibilityLevel::INTERNAL)
    end

    it 'should set a project as private' do
      project = attributes_for(:project, :private)
      post api("/projects/user/#{user.id}", admin), project
      expect(json_response['public']).to be_falsey
      expect(json_response['visibility_level']).to eq(Gitlab::VisibilityLevel::PRIVATE)
    end

    it 'should set a project as private using :public' do
      project = attributes_for(:project, { public: false })
      post api("/projects/user/#{user.id}", admin), project
      expect(json_response['public']).to be_falsey
      expect(json_response['visibility_level']).to eq(Gitlab::VisibilityLevel::PRIVATE)
    end
  end

  describe "POST /projects/:id/uploads" do
    before { project }

    it "uploads the file and returns its info" do
      post api("/projects/#{project.id}/uploads", user), file: fixture_file_upload(Rails.root + "spec/fixtures/dk.png", "image/png")

      expect(response.status).to be(201)
      expect(json_response['alt']).to eq("dk")
      expect(json_response['url']).to start_with("/uploads/")
      expect(json_response['url']).to end_with("/dk.png")
      expect(json_response['is_image']).to eq(true)
    end
  end

  describe 'GET /projects/:id' do
    before { project }
    before { project_member }

    it 'should return a project by id' do
      get api("/projects/#{project.id}", user)
      expect(response.status).to eq(200)
      expect(json_response['name']).to eq(project.name)
      expect(json_response['owner']['username']).to eq(user.username)
    end

    it 'should return a project by path name' do
      get api("/projects/#{project.id}", user)
      expect(response.status).to eq(200)
      expect(json_response['name']).to eq(project.name)
    end

    it 'should return a 404 error if not found' do
      get api('/projects/42', user)
      expect(response.status).to eq(404)
      expect(json_response['message']).to eq('404 Project Not Found')
    end

    it 'should return a 404 error if user is not a member' do
      other_user = create(:user)
      get api("/projects/#{project.id}", other_user)
      expect(response.status).to eq(404)
    end

    it 'should handle users with dots' do
      dot_user = create(:user, username: 'dot.user')
      project = create(:project, creator_id: dot_user.id, namespace: dot_user.namespace)

      get api("/projects/#{dot_user.namespace.name}%2F#{project.path}", dot_user)
      expect(response.status).to eq(200)
      expect(json_response['name']).to eq(project.name)
    end

    describe 'permissions' do
      context 'all projects' do
        before { project.team << [user, :master] }

        it 'contains permission information' do
          get api("/projects", user)

          expect(response.status).to eq(200)
          expect(json_response.first['permissions']['project_access']['access_level']).
              to eq(Gitlab::Access::MASTER)
          expect(json_response.first['permissions']['group_access']).to be_nil
        end
      end

      context 'personal project' do
        it 'sets project access and returns 200' do
          project.team << [user, :master]
          get api("/projects/#{project.id}", user)

          expect(response.status).to eq(200)
          expect(json_response['permissions']['project_access']['access_level']).
            to eq(Gitlab::Access::MASTER)
          expect(json_response['permissions']['group_access']).to be_nil
        end
      end

      context 'group project' do
        let(:project2) { create(:project, group: create(:group)) }

        before { project2.group.add_owner(user) }

        it 'should set the owner and return 200' do
          get api("/projects/#{project2.id}", user)

          expect(response.status).to eq(200)
          expect(json_response['permissions']['project_access']).to be_nil
          expect(json_response['permissions']['group_access']['access_level']).
            to eq(Gitlab::Access::OWNER)
        end
      end
    end
  end

  describe 'GET /projects/:id/events' do
    before { project_member2 }

    context 'valid request' do
      before do
        note = create(:note_on_issue, note: 'What an awesome day!', project: project)
        EventCreateService.new.leave_note(note, note.author)
        get api("/projects/#{project.id}/events", user)
      end

      it { expect(response.status).to eq(200) }

      context 'joined event' do
        let(:json_event) { json_response[1] }

        it { expect(json_event['action_name']).to eq('joined') }
        it { expect(json_event['project_id'].to_i).to eq(project.id) }
        it { expect(json_event['author_username']).to eq(user3.username) }
        it { expect(json_event['author']['name']).to eq(user3.name) }
      end

      context 'comment event' do
        let(:json_event) { json_response.first }

        it { expect(json_event['action_name']).to eq('commented on') }
        it { expect(json_event['note']['body']).to eq('What an awesome day!') }
      end
    end

    it 'should return a 404 error if not found' do
      get api('/projects/42/events', user)
      expect(response.status).to eq(404)
      expect(json_response['message']).to eq('404 Project Not Found')
    end

    it 'should return a 404 error if user is not a member' do
      other_user = create(:user)
      get api("/projects/#{project.id}/events", other_user)
      expect(response.status).to eq(404)
    end
  end

  describe 'GET /projects/:id/snippets' do
    before { snippet }

    it 'should return an array of project snippets' do
      get api("/projects/#{project.id}/snippets", user)
      expect(response.status).to eq(200)
      expect(json_response).to be_an Array
      expect(json_response.first['title']).to eq(snippet.title)
    end
  end

  describe 'GET /projects/:id/snippets/:snippet_id' do
    it 'should return a project snippet' do
      get api("/projects/#{project.id}/snippets/#{snippet.id}", user)
      expect(response.status).to eq(200)
      expect(json_response['title']).to eq(snippet.title)
    end

    it 'should return a 404 error if snippet id not found' do
      get api("/projects/#{project.id}/snippets/1234", user)
      expect(response.status).to eq(404)
    end
  end

  describe 'POST /projects/:id/snippets' do
    it 'should create a new project snippet' do
      post api("/projects/#{project.id}/snippets", user),
        title: 'api test', file_name: 'sample.rb', code: 'test',
        visibility_level: '0'
      expect(response.status).to eq(201)
      expect(json_response['title']).to eq('api test')
    end

    it 'should return a 400 error if invalid snippet is given' do
      post api("/projects/#{project.id}/snippets", user)
      expect(status).to eq(400)
    end
  end

  describe 'PUT /projects/:id/snippets/:snippet_id' do
    it 'should update an existing project snippet' do
      put api("/projects/#{project.id}/snippets/#{snippet.id}", user),
        code: 'updated code'
      expect(response.status).to eq(200)
      expect(json_response['title']).to eq('example')
      expect(snippet.reload.content).to eq('updated code')
    end

    it 'should update an existing project snippet with new title' do
      put api("/projects/#{project.id}/snippets/#{snippet.id}", user),
        title: 'other api test'
      expect(response.status).to eq(200)
      expect(json_response['title']).to eq('other api test')
    end
  end

  describe 'DELETE /projects/:id/snippets/:snippet_id' do
    before { snippet }

    it 'should delete existing project snippet' do
      expect do
        delete api("/projects/#{project.id}/snippets/#{snippet.id}", user)
      end.to change { Snippet.count }.by(-1)
      expect(response.status).to eq(200)
    end

    it 'should return 404 when deleting unknown snippet id' do
      delete api("/projects/#{project.id}/snippets/1234", user)
      expect(response.status).to eq(404)
    end
  end

  describe 'GET /projects/:id/snippets/:snippet_id/raw' do
    it 'should get a raw project snippet' do
      get api("/projects/#{project.id}/snippets/#{snippet.id}/raw", user)
      expect(response.status).to eq(200)
    end

    it 'should return a 404 error if raw project snippet not found' do
      get api("/projects/#{project.id}/snippets/5555/raw", user)
      expect(response.status).to eq(404)
    end
  end

  describe :deploy_keys do
    let(:deploy_keys_project) { create(:deploy_keys_project, project: project) }
    let(:deploy_key) { deploy_keys_project.deploy_key }

    describe 'GET /projects/:id/keys' do
      before { deploy_key }

      it 'should return array of ssh keys' do
        get api("/projects/#{project.id}/keys", user)
        expect(response.status).to eq(200)
        expect(json_response).to be_an Array
        expect(json_response.first['title']).to eq(deploy_key.title)
      end
    end

    describe 'GET /projects/:id/keys/:key_id' do
      it 'should return a single key' do
        get api("/projects/#{project.id}/keys/#{deploy_key.id}", user)
        expect(response.status).to eq(200)
        expect(json_response['title']).to eq(deploy_key.title)
      end

      it 'should return 404 Not Found with invalid ID' do
        get api("/projects/#{project.id}/keys/404", user)
        expect(response.status).to eq(404)
      end
    end

    describe 'POST /projects/:id/keys' do
      it 'should not create an invalid ssh key' do
        post api("/projects/#{project.id}/keys", user), { title: 'invalid key' }
        expect(response.status).to eq(400)
        expect(json_response['message']['key']).to eq([
          'can\'t be blank',
          'is too short (minimum is 0 characters)',
          'is invalid'
        ])
      end

      it 'should not create a key without title' do
        post api("/projects/#{project.id}/keys", user), key: 'some key'
        expect(response.status).to eq(400)
        expect(json_response['message']['title']).to eq([
          'can\'t be blank',
          'is too short (minimum is 0 characters)'
        ])
      end

      it 'should create new ssh key' do
        key_attrs = attributes_for :key
        expect do
          post api("/projects/#{project.id}/keys", user), key_attrs
        end.to change{ project.deploy_keys.count }.by(1)
      end
    end

    describe 'DELETE /projects/:id/keys/:key_id' do
      before { deploy_key }

      it 'should delete existing key' do
        expect do
          delete api("/projects/#{project.id}/keys/#{deploy_key.id}", user)
        end.to change{ project.deploy_keys.count }.by(-1)
      end

      it 'should return 404 Not Found with invalid ID' do
        delete api("/projects/#{project.id}/keys/404", user)
        expect(response.status).to eq(404)
      end
    end
  end

  describe :fork_admin do
    let(:project_fork_target) { create(:project) }
    let(:project_fork_source) { create(:project, :public) }

    describe 'POST /projects/:id/fork/:forked_from_id' do
      let(:new_project_fork_source) { create(:project, :public) }

      it "shouldn't available for non admin users" do
        post api("/projects/#{project_fork_target.id}/fork/#{project_fork_source.id}", user)
        expect(response.status).to eq(403)
      end

      it 'should allow project to be forked from an existing project' do
        expect(project_fork_target.forked?).not_to be_truthy
        post api("/projects/#{project_fork_target.id}/fork/#{project_fork_source.id}", admin)
        expect(response.status).to eq(201)
        project_fork_target.reload
        expect(project_fork_target.forked_from_project.id).to eq(project_fork_source.id)
        expect(project_fork_target.forked_project_link).not_to be_nil
        expect(project_fork_target.forked?).to be_truthy
      end

      it 'should fail if forked_from project which does not exist' do
        post api("/projects/#{project_fork_target.id}/fork/9999", admin)
        expect(response.status).to eq(404)
      end

      it 'should fail with 409 if already forked' do
        post api("/projects/#{project_fork_target.id}/fork/#{project_fork_source.id}", admin)
        project_fork_target.reload
        expect(project_fork_target.forked_from_project.id).to eq(project_fork_source.id)
        post api("/projects/#{project_fork_target.id}/fork/#{new_project_fork_source.id}", admin)
        expect(response.status).to eq(409)
        project_fork_target.reload
        expect(project_fork_target.forked_from_project.id).to eq(project_fork_source.id)
        expect(project_fork_target.forked?).to be_truthy
      end
    end

    describe 'DELETE /projects/:id/fork' do

      it "shouldn't be visible to users outside group" do
        delete api("/projects/#{project_fork_target.id}/fork", user)
        expect(response.status).to eq(404)
      end

      context 'when users belong to project group' do
        let(:project_fork_target) { create(:project, group: create(:group)) }

        before do
          project_fork_target.group.add_owner user
          project_fork_target.group.add_developer user2
        end

        it 'should be forbidden to non-owner users' do
          delete api("/projects/#{project_fork_target.id}/fork", user2)
          expect(response.status).to eq(403)
        end

        it 'should make forked project unforked' do
          post api("/projects/#{project_fork_target.id}/fork/#{project_fork_source.id}", admin)
          project_fork_target.reload
          expect(project_fork_target.forked_from_project).not_to be_nil
          expect(project_fork_target.forked?).to be_truthy
          delete api("/projects/#{project_fork_target.id}/fork", admin)
          expect(response.status).to eq(200)
          project_fork_target.reload
          expect(project_fork_target.forked_from_project).to be_nil
          expect(project_fork_target.forked?).not_to be_truthy
        end

        it 'should be idempotent if not forked' do
          expect(project_fork_target.forked_from_project).to be_nil
          delete api("/projects/#{project_fork_target.id}/fork", admin)
          expect(response.status).to eq(200)
          expect(project_fork_target.reload.forked_from_project).to be_nil
        end
      end
    end
  end

  describe "POST /projects/:id/share" do
    let(:group) { create(:group) }

    it "should share project with group" do
      expect do
        post api("/projects/#{project.id}/share", user), group_id: group.id, group_access: Gitlab::Access::DEVELOPER
      end.to change { ProjectGroupLink.count }.by(1)

      expect(response.status).to eq 201
      expect(json_response['group_id']).to eq group.id
      expect(json_response['group_access']).to eq Gitlab::Access::DEVELOPER
    end

    it "should return a 400 error when group id is not given" do
      post api("/projects/#{project.id}/share", user), group_access: Gitlab::Access::DEVELOPER
      expect(response.status).to eq 400
    end

    it "should return a 400 error when access level is not given" do
      post api("/projects/#{project.id}/share", user), group_id: group.id
      expect(response.status).to eq 400
    end

    it "should return a 400 error when sharing is disabled" do
      project.namespace.update(share_with_group_lock: true)
      post api("/projects/#{project.id}/share", user), group_id: group.id, group_access: Gitlab::Access::DEVELOPER
      expect(response.status).to eq 400
    end

    it "should return a 409 error when wrong params passed" do
      post api("/projects/#{project.id}/share", user), group_id: group.id, group_access: 1234
      expect(response.status).to eq 409
      expect(json_response['message']).to eq 'Group access is not included in the list'
    end
  end

  describe 'GET /projects/search/:query' do
    let!(:query) { 'query'}
    let!(:search)           { create(:empty_project, name: query, creator_id: user.id, namespace: user.namespace) }
    let!(:pre)              { create(:empty_project, name: "pre_#{query}", creator_id: user.id, namespace: user.namespace) }
    let!(:post)             { create(:empty_project, name: "#{query}_post", creator_id: user.id, namespace: user.namespace) }
    let!(:pre_post)         { create(:empty_project, name: "pre_#{query}_post", creator_id: user.id, namespace: user.namespace) }
    let!(:unfound)          { create(:empty_project, name: 'unfound', creator_id: user.id, namespace: user.namespace) }
    let!(:internal)         { create(:empty_project, :internal, name: "internal #{query}") }
    let!(:unfound_internal) { create(:empty_project, :internal, name: 'unfound internal') }
    let!(:public)           { create(:empty_project, :public, name: "public #{query}") }
    let!(:unfound_public)   { create(:empty_project, :public, name: 'unfound public') }

    context 'when unauthenticated' do
      it 'should return authentication error' do
        get api("/projects/search/#{query}")
        expect(response.status).to eq(401)
      end
    end

    context 'when authenticated' do
      it 'should return an array of projects' do
        get api("/projects/search/#{query}",user)
        expect(response.status).to eq(200)
        expect(json_response).to be_an Array
        expect(json_response.size).to eq(6)
        json_response.each {|project| expect(project['name']).to match(/.*query.*/)}
      end
    end

    context 'when authenticated as a different user' do
      it 'should return matching public projects' do
        get api("/projects/search/#{query}", user2)
        expect(response.status).to eq(200)
        expect(json_response).to be_an Array
        expect(json_response.size).to eq(2)
        json_response.each {|project| expect(project['name']).to match(/(internal|public) query/)}
      end
    end
  end

  describe 'PUT /projects/:id̈́' do
    before { project }
    before { user }
    before { user3 }
    before { user4 }
    before { project3 }
    before { project4 }
    before { project_member3 }
    before { project_member2 }

    context 'when unauthenticated' do
      it 'should return authentication error' do
        project_param = { name: 'bar' }
        put api("/projects/#{project.id}"), project_param
        expect(response.status).to eq(401)
      end
    end

    context 'when authenticated as project owner' do
      it 'should update name' do
        project_param = { name: 'bar' }
        put api("/projects/#{project.id}", user), project_param
        expect(response.status).to eq(200)
        project_param.each_pair do |k, v|
          expect(json_response[k.to_s]).to eq(v)
        end
      end

      it 'should update visibility_level' do
        project_param = { visibility_level: 20 }
        put api("/projects/#{project3.id}", user), project_param
        expect(response.status).to eq(200)
        project_param.each_pair do |k, v|
          expect(json_response[k.to_s]).to eq(v)
        end
      end

      it 'should update visibility_level from public to private' do
        project3.update_attributes({ visibility_level: Gitlab::VisibilityLevel::PUBLIC })

        project_param = { public: false }
        put api("/projects/#{project3.id}", user), project_param
        expect(response.status).to eq(200)
        project_param.each_pair do |k, v|
          expect(json_response[k.to_s]).to eq(v)
        end
        expect(json_response['visibility_level']).to eq(Gitlab::VisibilityLevel::PRIVATE)
      end

      it 'should not update name to existing name' do
        project_param = { name: project3.name }
        put api("/projects/#{project.id}", user), project_param
        expect(response.status).to eq(400)
        expect(json_response['message']['name']).to eq(['has already been taken'])
      end

      it 'should update path & name to existing path & name in different namespace' do
        project_param = { path: project4.path, name: project4.name }
        put api("/projects/#{project3.id}", user), project_param
        expect(response.status).to eq(200)
        project_param.each_pair do |k, v|
          expect(json_response[k.to_s]).to eq(v)
        end
      end
    end

    context 'when authenticated as project master' do
      it 'should update path' do
        project_param = { path: 'bar' }
        put api("/projects/#{project3.id}", user4), project_param
        expect(response.status).to eq(200)
        project_param.each_pair do |k, v|
          expect(json_response[k.to_s]).to eq(v)
        end
      end

      it 'should update other attributes' do
        project_param = { issues_enabled: true,
                          wiki_enabled: true,
                          snippets_enabled: true,
                          merge_requests_enabled: true,
                          description: 'new description' }

        put api("/projects/#{project3.id}", user4), project_param
        expect(response.status).to eq(200)
        project_param.each_pair do |k, v|
          expect(json_response[k.to_s]).to eq(v)
        end
      end

      it 'should not update path to existing path' do
        project_param = { path: project.path }
        put api("/projects/#{project3.id}", user4), project_param
        expect(response.status).to eq(400)
        expect(json_response['message']['path']).to eq(['has already been taken'])
      end

      it 'should not update name' do
        project_param = { name: 'bar' }
        put api("/projects/#{project3.id}", user4), project_param
        expect(response.status).to eq(403)
      end

      it 'should not update visibility_level' do
        project_param = { visibility_level: 20 }
        put api("/projects/#{project3.id}", user4), project_param
        expect(response.status).to eq(403)
      end
    end

    context 'when authenticated as project developer' do
      it 'should not update other attributes' do
        project_param = { path: 'bar',
                          issues_enabled: true,
                          wiki_enabled: true,
                          snippets_enabled: true,
                          merge_requests_enabled: true,
                          description: 'new description' }
        put api("/projects/#{project.id}", user3), project_param
        expect(response.status).to eq(403)
      end
    end
  end

  describe 'POST /projects/:id/archive' do
    context 'on an unarchived project' do
      it 'archives the project' do
        post api("/projects/#{project.id}/archive", user)

        expect(response.status).to eq(201)
        expect(json_response['archived']).to be_truthy
      end
    end

    context 'on an archived project' do
      before do
        project.archive!
      end

      it 'remains archived' do
        post api("/projects/#{project.id}/archive", user)

        expect(response.status).to eq(201)
        expect(json_response['archived']).to be_truthy
      end
    end

    context 'user without archiving rights to the project' do
      before do
        project.team << [user3, :developer]
      end

      it 'rejects the action' do
        post api("/projects/#{project.id}/archive", user3)

        expect(response.status).to eq(403)
      end
    end
  end

  describe 'POST /projects/:id/unarchive' do
    context 'on an unarchived project' do
      it 'remains unarchived' do
        post api("/projects/#{project.id}/unarchive", user)

        expect(response.status).to eq(201)
        expect(json_response['archived']).to be_falsey
      end
    end

    context 'on an archived project' do
      before do
        project.archive!
      end

      it 'unarchives the project' do
        post api("/projects/#{project.id}/unarchive", user)

        expect(response.status).to eq(201)
        expect(json_response['archived']).to be_falsey
      end
    end

    context 'user without archiving rights to the project' do
      before do
        project.team << [user3, :developer]
      end

      it 'rejects the action' do
        post api("/projects/#{project.id}/unarchive", user3)

        expect(response.status).to eq(403)
      end
    end
  end

  describe 'POST /projects/:id/star' do
    context 'on an unstarred project' do
      it 'stars the project' do
        expect { post api("/projects/#{project.id}/star", user) }.to change { project.reload.star_count }.by(1)

        expect(response.status).to eq(201)
        expect(json_response['star_count']).to eq(1)
      end
    end

    context 'on a starred project' do
      before do
        user.toggle_star(project)
        project.reload
      end

      it 'does not modify the star count' do
        expect { post api("/projects/#{project.id}/star", user) }.not_to change { project.reload.star_count }

        expect(response.status).to eq(304)
      end
    end
  end

  describe 'DELETE /projects/:id/star' do
    context 'on a starred project' do
      before do
        user.toggle_star(project)
        project.reload
      end

      it 'unstars the project' do
        expect { delete api("/projects/#{project.id}/star", user) }.to change { project.reload.star_count }.by(-1)

        expect(response.status).to eq(200)
        expect(json_response['star_count']).to eq(0)
      end
    end

    context 'on an unstarred project' do
      it 'does not modify the star count' do
        expect { delete api("/projects/#{project.id}/star", user) }.not_to change { project.reload.star_count }

        expect(response.status).to eq(304)
      end
    end
  end

  describe 'DELETE /projects/:id' do
    context 'when authenticated as user' do
      it 'should remove project' do
        delete api("/projects/#{project.id}", user)
        expect(response.status).to eq(200)
      end

      it 'should not remove a project if not an owner' do
        user3 = create(:user)
        project.team << [user3, :developer]
        delete api("/projects/#{project.id}", user3)
        expect(response.status).to eq(403)
      end

      it 'should not remove a non existing project' do
        delete api('/projects/1328', user)
        expect(response.status).to eq(404)
      end

      it 'should not remove a project not attached to user' do
        delete api("/projects/#{project.id}", user2)
        expect(response.status).to eq(404)
      end
    end

    context 'when authenticated as admin' do
      it 'should remove any existing project' do
        delete api("/projects/#{project.id}", admin)
        expect(response.status).to eq(200)
      end

      it 'should not remove a non existing project' do
        delete api('/projects/1328', admin)
        expect(response.status).to eq(404)
      end
    end
  end
end
