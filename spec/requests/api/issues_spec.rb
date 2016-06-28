require 'spec_helper'

describe API::API, api: true  do
  include ApiHelpers
  let(:user)        { create(:user) }
  let(:user2)       { create(:user) }
  let(:non_member)  { create(:user) }
  let(:guest)       { create(:user) }
  let(:author)      { create(:author) }
  let(:assignee)    { create(:assignee) }
  let(:admin)       { create(:user, :admin) }
  let!(:project)    { create(:project, :public, creator_id: user.id, namespace: user.namespace ) }
  let!(:closed_issue) do
    create :closed_issue,
           author: user,
           assignee: user,
           project: project,
           state: :closed,
           milestone: milestone
  end
  let!(:confidential_issue) do
    create :issue,
           :confidential,
           project: project,
           author: author,
           assignee: assignee
  end
  let!(:issue) do
    create :issue,
           author: user,
           assignee: user,
           project: project,
           milestone: milestone
  end
  let!(:label) do
    create(:label, title: 'label', color: '#FFAABB', project: project)
  end
  let!(:label_link) { create(:label_link, label: label, target: issue) }
  let!(:milestone) { create(:milestone, title: '1.0.0', project: project) }
  let!(:empty_milestone) do
    create(:milestone, title: '2.0.0', project: project)
  end
  let!(:note) { create(:note_on_issue, author: user, project: project, noteable: issue) }

  before do
    project.team << [user, :reporter]
    project.team << [guest, :guest]
  end

  describe "GET /issues" do
    context "when unauthenticated" do
      it "should return authentication error" do
        get api("/issues")
        expect(response.status).to eq(401)
      end
    end

    context "when authenticated" do
      it "should return an array of issues" do
        get api("/issues", user)
        expect(response.status).to eq(200)
        expect(json_response).to be_an Array
        expect(json_response.first['title']).to eq(issue.title)
      end

      it "should add pagination headers and keep query params" do
        get api("/issues?state=closed&per_page=3", user)
        expect(response.headers['Link']).to eq(
          '<http://www.example.com/api/v3/issues?page=1&per_page=3&private_token=%s&state=closed>; rel="first", <http://www.example.com/api/v3/issues?page=1&per_page=3&private_token=%s&state=closed>; rel="last"' % [user.private_token, user.private_token]
        )
      end

      it 'should return an array of closed issues' do
        get api('/issues?state=closed', user)
        expect(response.status).to eq(200)
        expect(json_response).to be_an Array
        expect(json_response.length).to eq(1)
        expect(json_response.first['id']).to eq(closed_issue.id)
      end

      it 'should return an array of opened issues' do
        get api('/issues?state=opened', user)
        expect(response.status).to eq(200)
        expect(json_response).to be_an Array
        expect(json_response.length).to eq(1)
        expect(json_response.first['id']).to eq(issue.id)
      end

      it 'should return an array of all issues' do
        get api('/issues?state=all', user)
        expect(response.status).to eq(200)
        expect(json_response).to be_an Array
        expect(json_response.length).to eq(2)
        expect(json_response.first['id']).to eq(issue.id)
        expect(json_response.second['id']).to eq(closed_issue.id)
      end

      it 'should return an array of labeled issues' do
        get api("/issues?labels=#{label.title}", user)
        expect(response.status).to eq(200)
        expect(json_response).to be_an Array
        expect(json_response.length).to eq(1)
        expect(json_response.first['labels']).to eq([label.title])
      end

      it 'should return an array of labeled issues when at least one label matches' do
        get api("/issues?labels=#{label.title},foo,bar", user)
        expect(response.status).to eq(200)
        expect(json_response).to be_an Array
        expect(json_response.length).to eq(1)
        expect(json_response.first['labels']).to eq([label.title])
      end

      it 'should return an empty array if no issue matches labels' do
        get api('/issues?labels=foo,bar', user)
        expect(response.status).to eq(200)
        expect(json_response).to be_an Array
        expect(json_response.length).to eq(0)
      end

      it 'should return an array of labeled issues matching given state' do
        get api("/issues?labels=#{label.title}&state=opened", user)
        expect(response.status).to eq(200)
        expect(json_response).to be_an Array
        expect(json_response.length).to eq(1)
        expect(json_response.first['labels']).to eq([label.title])
        expect(json_response.first['state']).to eq('opened')
      end

      it 'should return an empty array if no issue matches labels and state filters' do
        get api("/issues?labels=#{label.title}&state=closed", user)
        expect(response.status).to eq(200)
        expect(json_response).to be_an Array
        expect(json_response.length).to eq(0)
      end
    end
  end

  describe "GET /projects/:id/issues" do
    let(:base_url) { "/projects/#{project.id}" }
    let(:title) { milestone.title }

    it 'should return project issues without confidential issues for non project members' do
      get api("#{base_url}/issues", non_member)
      expect(response.status).to eq(200)
      expect(json_response).to be_an Array
      expect(json_response.length).to eq(2)
      expect(json_response.first['title']).to eq(issue.title)
    end

    it 'should return project issues without confidential issues for project members with guest role' do
      get api("#{base_url}/issues", guest)
      expect(response.status).to eq(200)
      expect(json_response).to be_an Array
      expect(json_response.length).to eq(2)
      expect(json_response.first['title']).to eq(issue.title)
    end

    it 'should return project confidential issues for author' do
      get api("#{base_url}/issues", author)
      expect(response.status).to eq(200)
      expect(json_response).to be_an Array
      expect(json_response.length).to eq(3)
      expect(json_response.first['title']).to eq(issue.title)
    end

    it 'should return project confidential issues for assignee' do
      get api("#{base_url}/issues", assignee)
      expect(response.status).to eq(200)
      expect(json_response).to be_an Array
      expect(json_response.length).to eq(3)
      expect(json_response.first['title']).to eq(issue.title)
    end

    it 'should return project issues with confidential issues for project members' do
      get api("#{base_url}/issues", user)
      expect(response.status).to eq(200)
      expect(json_response).to be_an Array
      expect(json_response.length).to eq(3)
      expect(json_response.first['title']).to eq(issue.title)
    end

    it 'should return project confidential issues for admin' do
      get api("#{base_url}/issues", admin)
      expect(response.status).to eq(200)
      expect(json_response).to be_an Array
      expect(json_response.length).to eq(3)
      expect(json_response.first['title']).to eq(issue.title)
    end

    it 'should return an array of labeled project issues' do
      get api("#{base_url}/issues?labels=#{label.title}", user)
      expect(response.status).to eq(200)
      expect(json_response).to be_an Array
      expect(json_response.length).to eq(1)
      expect(json_response.first['labels']).to eq([label.title])
    end

    it 'should return an array of labeled project issues when at least one label matches' do
      get api("#{base_url}/issues?labels=#{label.title},foo,bar", user)
      expect(response.status).to eq(200)
      expect(json_response).to be_an Array
      expect(json_response.length).to eq(1)
      expect(json_response.first['labels']).to eq([label.title])
    end

    it 'should return an empty array if no project issue matches labels' do
      get api("#{base_url}/issues?labels=foo,bar", user)
      expect(response.status).to eq(200)
      expect(json_response).to be_an Array
      expect(json_response.length).to eq(0)
    end

    it 'should return an empty array if no issue matches milestone' do
      get api("#{base_url}/issues?milestone=#{empty_milestone.title}", user)
      expect(response.status).to eq(200)
      expect(json_response).to be_an Array
      expect(json_response.length).to eq(0)
    end

    it 'should return an empty array if milestone does not exist' do
      get api("#{base_url}/issues?milestone=foo", user)
      expect(response.status).to eq(200)
      expect(json_response).to be_an Array
      expect(json_response.length).to eq(0)
    end

    it 'should return an array of issues in given milestone' do
      get api("#{base_url}/issues?milestone=#{title}", user)
      expect(response.status).to eq(200)
      expect(json_response).to be_an Array
      expect(json_response.length).to eq(2)
      expect(json_response.first['id']).to eq(issue.id)
      expect(json_response.second['id']).to eq(closed_issue.id)
    end

    it 'should return an array of issues matching state in milestone' do
      get api("#{base_url}/issues?milestone=#{milestone.title}"\
              '&state=closed', user)
      expect(response.status).to eq(200)
      expect(json_response).to be_an Array
      expect(json_response.length).to eq(1)
      expect(json_response.first['id']).to eq(closed_issue.id)
    end
  end

  describe "GET /projects/:id/issues/:issue_id" do
    it 'exposes known attributes' do
      get api("/projects/#{project.id}/issues/#{issue.id}", user)

      expect(response.status).to eq(200)
      expect(json_response['id']).to eq(issue.id)
      expect(json_response['iid']).to eq(issue.iid)
      expect(json_response['project_id']).to eq(issue.project.id)
      expect(json_response['title']).to eq(issue.title)
      expect(json_response['description']).to eq(issue.description)
      expect(json_response['state']).to eq(issue.state)
      expect(json_response['created_at']).to be_present
      expect(json_response['updated_at']).to be_present
      expect(json_response['labels']).to eq(issue.label_names)
      expect(json_response['milestone']).to be_a Hash
      expect(json_response['assignee']).to be_a Hash
      expect(json_response['author']).to be_a Hash
    end

    it "should return a project issue by id" do
      get api("/projects/#{project.id}/issues/#{issue.id}", user)

      expect(response.status).to eq(200)
      expect(json_response['title']).to eq(issue.title)
      expect(json_response['iid']).to eq(issue.iid)
    end

    it 'should return a project issue by iid' do
      get api("/projects/#{project.id}/issues?iid=#{issue.iid}", user)
      expect(response.status).to eq 200
      expect(json_response.first['title']).to eq issue.title
      expect(json_response.first['id']).to eq issue.id
      expect(json_response.first['iid']).to eq issue.iid
    end

    it "should return 404 if issue id not found" do
      get api("/projects/#{project.id}/issues/54321", user)
      expect(response.status).to eq(404)
    end

    context 'confidential issues' do
      it "should return 404 for non project members" do
        get api("/projects/#{project.id}/issues/#{confidential_issue.id}", non_member)
        expect(response.status).to eq(404)
      end

      it "should return 404 for project members with guest role" do
        get api("/projects/#{project.id}/issues/#{confidential_issue.id}", guest)
        expect(response.status).to eq(404)
      end

      it "should return confidential issue for project members" do
        get api("/projects/#{project.id}/issues/#{confidential_issue.id}", user)
        expect(response.status).to eq(200)
        expect(json_response['title']).to eq(confidential_issue.title)
        expect(json_response['iid']).to eq(confidential_issue.iid)
      end

      it "should return confidential issue for author" do
        get api("/projects/#{project.id}/issues/#{confidential_issue.id}", author)
        expect(response.status).to eq(200)
        expect(json_response['title']).to eq(confidential_issue.title)
        expect(json_response['iid']).to eq(confidential_issue.iid)
      end

      it "should return confidential issue for assignee" do
        get api("/projects/#{project.id}/issues/#{confidential_issue.id}", assignee)
        expect(response.status).to eq(200)
        expect(json_response['title']).to eq(confidential_issue.title)
        expect(json_response['iid']).to eq(confidential_issue.iid)
      end

      it "should return confidential issue for admin" do
        get api("/projects/#{project.id}/issues/#{confidential_issue.id}", admin)
        expect(response.status).to eq(200)
        expect(json_response['title']).to eq(confidential_issue.title)
        expect(json_response['iid']).to eq(confidential_issue.iid)
      end
    end
  end

  describe "POST /projects/:id/issues" do
    it "should create a new project issue" do
      post api("/projects/#{project.id}/issues", user),
        title: 'new issue', labels: 'label, label2'
      expect(response.status).to eq(201)
      expect(json_response['title']).to eq('new issue')
      expect(json_response['description']).to be_nil
      expect(json_response['labels']).to eq(['label', 'label2'])
    end

    it "should return a 400 bad request if title not given" do
      post api("/projects/#{project.id}/issues", user), labels: 'label, label2'
      expect(response.status).to eq(400)
    end

    it 'should return 400 on invalid label names' do
      post api("/projects/#{project.id}/issues", user),
           title: 'new issue',
           labels: 'label, ?'
      expect(response.status).to eq(400)
      expect(json_response['message']['labels']['?']['title']).to eq(['is invalid'])
    end

    it 'should return 400 if title is too long' do
      post api("/projects/#{project.id}/issues", user),
           title: 'g' * 256
      expect(response.status).to eq(400)
      expect(json_response['message']['title']).to eq([
        'is too long (maximum is 255 characters)'
      ])
    end

    context 'when an admin or owner makes the request' do
      it 'accepts the creation date to be set' do
        creation_time = 2.weeks.ago
        post api("/projects/#{project.id}/issues", user),
          title: 'new issue', labels: 'label, label2', created_at: creation_time

        expect(response.status).to eq(201)
        expect(Time.parse(json_response['created_at'])).to be_within(1.second).of(creation_time)
      end
    end
  end

  describe 'POST /projects/:id/issues with spam filtering' do
    before do
      Grape::Endpoint.before_each do |endpoint|
        allow(endpoint).to receive(:check_for_spam?).and_return(true)
        allow(endpoint).to receive(:is_spam?).and_return(true)
      end
    end

    let(:params) do
      {
        title: 'new issue',
        description: 'content here',
        labels: 'label, label2'
      }
    end

    it "should not create a new project issue" do
      expect { post api("/projects/#{project.id}/issues", user), params }.not_to change(Issue, :count)
      expect(response.status).to eq(400)
      expect(json_response['message']).to eq({ "error" => "Spam detected" })

      spam_logs = SpamLog.all
      expect(spam_logs.count).to eq(1)
      expect(spam_logs[0].title).to eq('new issue')
      expect(spam_logs[0].description).to eq('content here')
      expect(spam_logs[0].user).to eq(user)
      expect(spam_logs[0].noteable_type).to eq('Issue')
      expect(spam_logs[0].project_id).to eq(project.id)
    end
  end

  describe "PUT /projects/:id/issues/:issue_id to update only title" do
    it "should update a project issue" do
      put api("/projects/#{project.id}/issues/#{issue.id}", user),
        title: 'updated title'
      expect(response.status).to eq(200)

      expect(json_response['title']).to eq('updated title')
    end

    it "should return 404 error if issue id not found" do
      put api("/projects/#{project.id}/issues/44444", user),
        title: 'updated title'
      expect(response.status).to eq(404)
    end

    it 'should return 400 on invalid label names' do
      put api("/projects/#{project.id}/issues/#{issue.id}", user),
          title: 'updated title',
          labels: 'label, ?'
      expect(response.status).to eq(400)
      expect(json_response['message']['labels']['?']['title']).to eq(['is invalid'])
    end

    context 'confidential issues' do
      it "should return 403 for non project members" do
        put api("/projects/#{project.id}/issues/#{confidential_issue.id}", non_member),
          title: 'updated title'
        expect(response.status).to eq(403)
      end

      it "should return 403 for project members with guest role" do
        put api("/projects/#{project.id}/issues/#{confidential_issue.id}", guest),
          title: 'updated title'
        expect(response.status).to eq(403)
      end

      it "should update a confidential issue for project members" do
        put api("/projects/#{project.id}/issues/#{confidential_issue.id}", user),
          title: 'updated title'
        expect(response.status).to eq(200)
        expect(json_response['title']).to eq('updated title')
      end

      it "should update a confidential issue for author" do
        put api("/projects/#{project.id}/issues/#{confidential_issue.id}", author),
          title: 'updated title'
        expect(response.status).to eq(200)
        expect(json_response['title']).to eq('updated title')
      end

      it "should update a confidential issue for admin" do
        put api("/projects/#{project.id}/issues/#{confidential_issue.id}", admin),
          title: 'updated title'
        expect(response.status).to eq(200)
        expect(json_response['title']).to eq('updated title')
      end
    end
  end

  describe 'PUT /projects/:id/issues/:issue_id to update labels' do
    let!(:label) { create(:label, title: 'dummy', project: project) }
    let!(:label_link) { create(:label_link, label: label, target: issue) }

    it 'should not update labels if not present' do
      put api("/projects/#{project.id}/issues/#{issue.id}", user),
          title: 'updated title'
      expect(response.status).to eq(200)
      expect(json_response['labels']).to eq([label.title])
    end

    it 'should remove all labels' do
      put api("/projects/#{project.id}/issues/#{issue.id}", user),
          labels: ''
      expect(response.status).to eq(200)
      expect(json_response['labels']).to eq([])
    end

    it 'should update labels' do
      put api("/projects/#{project.id}/issues/#{issue.id}", user),
          labels: 'foo,bar'
      expect(response.status).to eq(200)
      expect(json_response['labels']).to include 'foo'
      expect(json_response['labels']).to include 'bar'
    end

    it 'should return 400 on invalid label names' do
      put api("/projects/#{project.id}/issues/#{issue.id}", user),
          labels: 'label, ?'
      expect(response.status).to eq(400)
      expect(json_response['message']['labels']['?']['title']).to eq(['is invalid'])
    end

    it 'should allow special label names' do
      put api("/projects/#{project.id}/issues/#{issue.id}", user),
          labels: 'label:foo, label-bar,label_bar,label/bar'
      expect(response.status).to eq(200)
      expect(json_response['labels']).to include 'label:foo'
      expect(json_response['labels']).to include 'label-bar'
      expect(json_response['labels']).to include 'label_bar'
      expect(json_response['labels']).to include 'label/bar'
    end

    it 'should return 400 if title is too long' do
      put api("/projects/#{project.id}/issues/#{issue.id}", user),
          title: 'g' * 256
      expect(response.status).to eq(400)
      expect(json_response['message']['title']).to eq([
        'is too long (maximum is 255 characters)'
      ])
    end
  end

  describe "PUT /projects/:id/issues/:issue_id to update state and label" do
    it "should update a project issue" do
      put api("/projects/#{project.id}/issues/#{issue.id}", user),
        labels: 'label2', state_event: "close"
      expect(response.status).to eq(200)

      expect(json_response['labels']).to include 'label2'
      expect(json_response['state']).to eq "closed"
    end

    context 'when an admin or owner makes the request' do
      it 'accepts the update date to be set' do
        update_time = 2.weeks.ago
        put api("/projects/#{project.id}/issues/#{issue.id}", user),
          labels: 'label3', state_event: 'close', updated_at: update_time
        expect(response.status).to eq(200)

        expect(json_response['labels']).to include 'label3'
        expect(Time.parse(json_response['updated_at'])).to be_within(1.second).of(update_time)
      end
    end
  end

  describe "DELETE /projects/:id/issues/:issue_id" do
    it "rejects a non member from deleting an issue" do
      delete api("/projects/#{project.id}/issues/#{issue.id}", non_member)
      expect(response.status).to be(403)
    end

    it "rejects a developer from deleting an issue" do
      delete api("/projects/#{project.id}/issues/#{issue.id}", author)
      expect(response.status).to be(403)
    end

    context "when the user is project owner" do
      let(:owner)     { create(:user) }
      let(:project)   { create(:project, namespace: owner.namespace) }

      it "deletes the issue if an admin requests it" do
        delete api("/projects/#{project.id}/issues/#{issue.id}", owner)
        expect(response.status).to eq(200)
        expect(json_response['state']).to eq 'opened'
      end
    end
  end

  describe '/projects/:id/issues/:issue_id/move' do
    let!(:target_project) { create(:project, path: 'project2', creator_id: user.id, namespace: user.namespace ) }
    let!(:target_project2) { create(:project, creator_id: non_member.id, namespace: non_member.namespace ) }

    it 'moves an issue' do
      post api("/projects/#{project.id}/issues/#{issue.id}/move", user),
               to_project_id: target_project.id

      expect(response.status).to eq(201)
      expect(json_response['project_id']).to eq(target_project.id)
    end

    context 'when source and target projects are the same' do
      it 'returns 400 when trying to move an issue' do
        post api("/projects/#{project.id}/issues/#{issue.id}/move", user),
                 to_project_id: project.id

        expect(response.status).to eq(400)
        expect(json_response['message']).to eq('Cannot move issue to project it originates from!')
      end
    end

    context 'when the user does not have the permission to move issues' do
      it 'returns 400 when trying to move an issue' do
        post api("/projects/#{project.id}/issues/#{issue.id}/move", user),
                 to_project_id: target_project2.id

        expect(response.status).to eq(400)
        expect(json_response['message']).to eq('Cannot move issue due to insufficient permissions!')
      end
    end

    it 'moves the issue to another namespace if I am admin' do
      post api("/projects/#{project.id}/issues/#{issue.id}/move", admin),
               to_project_id: target_project2.id

      expect(response.status).to eq(201)
      expect(json_response['project_id']).to eq(target_project2.id)
    end

    context 'when issue does not exist' do
      it 'returns 404 when trying to move an issue' do
        post api("/projects/#{project.id}/issues/123/move", user),
                 to_project_id: target_project.id

        expect(response.status).to eq(404)
      end
    end

    context 'when source project does not exist' do
      it 'returns 404 when trying to move an issue' do
        post api("/projects/123/issues/#{issue.id}/move", user),
                 to_project_id: target_project.id

        expect(response.status).to eq(404)
      end
    end

    context 'when target project does not exist' do
      it 'returns 404 when trying to move an issue' do
        post api("/projects/#{project.id}/issues/#{issue.id}/move", user),
                 to_project_id: 123

        expect(response.status).to eq(404)
      end
    end
  end

  describe 'POST :id/issues/:issue_id/subscription' do
    it 'subscribes to an issue' do
      post api("/projects/#{project.id}/issues/#{issue.id}/subscription", user2)

      expect(response.status).to eq(201)
      expect(json_response['subscribed']).to eq(true)
    end

    it 'returns 304 if already subscribed' do
      post api("/projects/#{project.id}/issues/#{issue.id}/subscription", user)

      expect(response.status).to eq(304)
    end

    it 'returns 404 if the issue is not found' do
      post api("/projects/#{project.id}/issues/123/subscription", user)

      expect(response.status).to eq(404)
    end

    it 'returns 404 if the issue is confidential' do
      post api("/projects/#{project.id}/issues/#{confidential_issue.id}/subscription", non_member)

      expect(response.status).to eq(404)
    end
  end

  describe 'DELETE :id/issues/:issue_id/subscription' do
    it 'unsubscribes from an issue' do
      delete api("/projects/#{project.id}/issues/#{issue.id}/subscription", user)

      expect(response.status).to eq(200)
      expect(json_response['subscribed']).to eq(false)
    end

    it 'returns 304 if not subscribed' do
      delete api("/projects/#{project.id}/issues/#{issue.id}/subscription", user2)

      expect(response.status).to eq(304)
    end

    it 'returns 404 if the issue is not found' do
      delete api("/projects/#{project.id}/issues/123/subscription", user)

      expect(response.status).to eq(404)
    end

    it 'returns 404 if the issue is confidential' do
      delete api("/projects/#{project.id}/issues/#{confidential_issue.id}/subscription", non_member)

      expect(response.status).to eq(404)
    end
  end
end
