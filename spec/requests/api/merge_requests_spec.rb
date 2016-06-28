require "spec_helper"

describe API::API, api: true  do
  include ApiHelpers
  let(:base_time)   { Time.now }
  let(:user)        { create(:user) }
  let(:admin)       { create(:user, :admin) }
  let(:non_member)  { create(:user) }
  let!(:project)    { create(:project, creator_id: user.id, namespace: user.namespace) }
  let!(:merge_request) { create(:merge_request, :simple, author: user, assignee: user, source_project: project, target_project: project, title: "Test", created_at: base_time) }
  let!(:merge_request_closed) { create(:merge_request, state: "closed", author: user, assignee: user, source_project: project, target_project: project, title: "Closed test", created_at: base_time + 1.second) }
  let!(:merge_request_merged) { create(:merge_request, state: "merged", author: user, assignee: user, source_project: project, target_project: project, title: "Merged test", created_at: base_time + 2.seconds) }
  let!(:note)       { create(:note_on_merge_request, author: user, project: project, noteable: merge_request, note: "a comment on a MR") }
  let!(:note2)      { create(:note_on_merge_request, author: user, project: project, noteable: merge_request, note: "another comment on a MR") }
  let(:milestone)   { create(:milestone, title: '1.0.0', project: project) }

  before do
    project.team << [user, :reporters]
  end

  describe "GET /projects/:id/merge_requests" do
    context "when unauthenticated" do
      it "should return authentication error" do
        get api("/projects/#{project.id}/merge_requests")
        expect(response.status).to eq(401)
      end
    end

    context "when authenticated" do
      it "should return an array of all merge_requests" do
        get api("/projects/#{project.id}/merge_requests", user)
        expect(response.status).to eq(200)
        expect(json_response).to be_an Array
        expect(json_response.length).to eq(3)
        expect(json_response.last['title']).to eq(merge_request.title)
      end

      it "should return an array of all merge_requests" do
        get api("/projects/#{project.id}/merge_requests?state", user)
        expect(response.status).to eq(200)
        expect(json_response).to be_an Array
        expect(json_response.length).to eq(3)
        expect(json_response.last['title']).to eq(merge_request.title)
      end

      it "should return an array of open merge_requests" do
        get api("/projects/#{project.id}/merge_requests?state=opened", user)
        expect(response.status).to eq(200)
        expect(json_response).to be_an Array
        expect(json_response.length).to eq(1)
        expect(json_response.last['title']).to eq(merge_request.title)
      end

      it "should return an array of closed merge_requests" do
        get api("/projects/#{project.id}/merge_requests?state=closed", user)
        expect(response.status).to eq(200)
        expect(json_response).to be_an Array
        expect(json_response.length).to eq(1)
        expect(json_response.first['title']).to eq(merge_request_closed.title)
      end

      it "should return an array of merged merge_requests" do
        get api("/projects/#{project.id}/merge_requests?state=merged", user)
        expect(response.status).to eq(200)
        expect(json_response).to be_an Array
        expect(json_response.length).to eq(1)
        expect(json_response.first['title']).to eq(merge_request_merged.title)
      end

      context "with ordering" do
        before do
          @mr_later = mr_with_later_created_and_updated_at_time
          @mr_earlier = mr_with_earlier_created_and_updated_at_time
        end

        it "should return an array of merge_requests in ascending order" do
          get api("/projects/#{project.id}/merge_requests?sort=asc", user)
          expect(response.status).to eq(200)
          expect(json_response).to be_an Array
          expect(json_response.length).to eq(3)
          response_dates = json_response.map{ |merge_request| merge_request['created_at'] }
          expect(response_dates).to eq(response_dates.sort)
        end

        it "should return an array of merge_requests in descending order" do
          get api("/projects/#{project.id}/merge_requests?sort=desc", user)
          expect(response.status).to eq(200)
          expect(json_response).to be_an Array
          expect(json_response.length).to eq(3)
          response_dates = json_response.map{ |merge_request| merge_request['created_at'] }
          expect(response_dates).to eq(response_dates.sort.reverse)
        end

        it "should return an array of merge_requests ordered by updated_at" do
          get api("/projects/#{project.id}/merge_requests?order_by=updated_at", user)
          expect(response.status).to eq(200)
          expect(json_response).to be_an Array
          expect(json_response.length).to eq(3)
          response_dates = json_response.map{ |merge_request| merge_request['updated_at'] }
          expect(response_dates).to eq(response_dates.sort.reverse)
        end

        it "should return an array of merge_requests ordered by created_at" do
          get api("/projects/#{project.id}/merge_requests?order_by=created_at&sort=asc", user)
          expect(response.status).to eq(200)
          expect(json_response).to be_an Array
          expect(json_response.length).to eq(3)
          response_dates = json_response.map{ |merge_request| merge_request['created_at'] }
          expect(response_dates).to eq(response_dates.sort)
        end
      end
    end
  end

  describe "GET /projects/:id/merge_requests/:merge_request_id" do
    it 'exposes known attributes' do
      get api("/projects/#{project.id}/merge_requests/#{merge_request.id}", user)

      expect(response.status).to eq(200)
      expect(json_response['id']).to eq(merge_request.id)
      expect(json_response['iid']).to eq(merge_request.iid)
      expect(json_response['project_id']).to eq(merge_request.project.id)
      expect(json_response['title']).to eq(merge_request.title)
      expect(json_response['description']).to eq(merge_request.description)
      expect(json_response['state']).to eq(merge_request.state)
      expect(json_response['created_at']).to be_present
      expect(json_response['updated_at']).to be_present
      expect(json_response['labels']).to eq(merge_request.label_names)
      expect(json_response['milestone']).to be_nil
      expect(json_response['assignee']).to be_a Hash
      expect(json_response['author']).to be_a Hash
      expect(json_response['target_branch']).to eq(merge_request.target_branch)
      expect(json_response['source_branch']).to eq(merge_request.source_branch)
      expect(json_response['upvotes']).to eq(0)
      expect(json_response['downvotes']).to eq(0)
      expect(json_response['source_project_id']).to eq(merge_request.source_project.id)
      expect(json_response['target_project_id']).to eq(merge_request.target_project.id)
      expect(json_response['work_in_progress']).to be_falsy
      expect(json_response['merge_when_build_succeeds']).to be_falsy
      expect(json_response['merge_status']).to eq('can_be_merged')
    end

    it "should return merge_request" do
      get api("/projects/#{project.id}/merge_requests/#{merge_request.id}", user)
      expect(response.status).to eq(200)
      expect(json_response['title']).to eq(merge_request.title)
      expect(json_response['iid']).to eq(merge_request.iid)
      expect(json_response['work_in_progress']).to eq(false)
      expect(json_response['merge_status']).to eq('can_be_merged')
    end

    it 'should return merge_request by iid' do
      url = "/projects/#{project.id}/merge_requests?iid=#{merge_request.iid}"
      get api(url, user)
      expect(response.status).to eq 200
      expect(json_response.first['title']).to eq merge_request.title
      expect(json_response.first['id']).to eq merge_request.id
    end

    it "should return a 404 error if merge_request_id not found" do
      get api("/projects/#{project.id}/merge_requests/999", user)
      expect(response.status).to eq(404)
    end

    context 'Work in Progress' do
      let!(:merge_request_wip) { create(:merge_request, author: user, assignee: user, source_project: project, target_project: project, title: "WIP: Test", created_at: base_time + 1.second) }

      it "should return merge_request" do
        get api("/projects/#{project.id}/merge_requests/#{merge_request_wip.id}", user)
        expect(response.status).to eq(200)
        expect(json_response['work_in_progress']).to eq(true)
      end
    end
  end

  describe 'GET /projects/:id/merge_requests/:merge_request_id/commits' do
    context 'valid merge request' do
      before { get api("/projects/#{project.id}/merge_requests/#{merge_request.id}/commits", user) }
      let(:commit) { merge_request.commits.first }

      it { expect(response.status).to eq 200 }
      it { expect(json_response.size).to eq(merge_request.commits.size) }
      it { expect(json_response.first['id']).to eq(commit.id) }
      it { expect(json_response.first['title']).to eq(commit.title) }
    end

    it 'returns a 404 when merge_request_id not found' do
      get api("/projects/#{project.id}/merge_requests/999/commits", user)
      expect(response.status).to eq(404)
    end
  end

  describe 'GET /projects/:id/merge_requests/:merge_request_id/changes' do
    it 'should return the change information of the merge_request' do
      get api("/projects/#{project.id}/merge_requests/#{merge_request.id}/changes", user)
      expect(response.status).to eq 200
      expect(json_response['changes'].size).to eq(merge_request.diffs.size)
    end

    it 'returns a 404 when merge_request_id not found' do
      get api("/projects/#{project.id}/merge_requests/999/changes", user)
      expect(response.status).to eq(404)
    end
  end

  describe "POST /projects/:id/merge_requests" do
    context 'between branches projects' do
      it "should return merge_request" do
        post api("/projects/#{project.id}/merge_requests", user),
             title: 'Test merge_request',
             source_branch: 'feature_conflict',
             target_branch: 'master',
             author: user,
             labels: 'label, label2',
             milestone_id: milestone.id
        expect(response.status).to eq(201)
        expect(json_response['title']).to eq('Test merge_request')
        expect(json_response['labels']).to eq(['label', 'label2'])
        expect(json_response['milestone']['id']).to eq(milestone.id)
      end

      it "should return 422 when source_branch equals target_branch" do
        post api("/projects/#{project.id}/merge_requests", user),
        title: "Test merge_request", source_branch: "master", target_branch: "master", author: user
        expect(response.status).to eq(422)
      end

      it "should return 400 when source_branch is missing" do
        post api("/projects/#{project.id}/merge_requests", user),
        title: "Test merge_request", target_branch: "master", author: user
        expect(response.status).to eq(400)
      end

      it "should return 400 when target_branch is missing" do
        post api("/projects/#{project.id}/merge_requests", user),
        title: "Test merge_request", source_branch: "markdown", author: user
        expect(response.status).to eq(400)
      end

      it "should return 400 when title is missing" do
        post api("/projects/#{project.id}/merge_requests", user),
        target_branch: 'master', source_branch: 'markdown'
        expect(response.status).to eq(400)
      end

      it 'should return 400 on invalid label names' do
        post api("/projects/#{project.id}/merge_requests", user),
             title: 'Test merge_request',
             source_branch: 'markdown',
             target_branch: 'master',
             author: user,
             labels: 'label, ?'
        expect(response.status).to eq(400)
        expect(json_response['message']['labels']['?']['title']).to eq(
          ['is invalid']
        )
      end

      context 'with existing MR' do
        before do
          post api("/projects/#{project.id}/merge_requests", user),
               title: 'Test merge_request',
               source_branch: 'feature_conflict',
               target_branch: 'master',
               author: user
          @mr = MergeRequest.all.last
        end

        it 'should return 409 when MR already exists for source/target' do
          expect do
            post api("/projects/#{project.id}/merge_requests", user),
                 title: 'New test merge_request',
                 source_branch: 'feature_conflict',
                 target_branch: 'master',
                 author: user
          end.to change { MergeRequest.count }.by(0)
          expect(response.status).to eq(409)
        end
      end
    end

    context 'forked projects' do
      let!(:user2) { create(:user) }
      let!(:fork_project) { create(:project, forked_from_project: project,  namespace: user2.namespace, creator_id: user2.id) }
      let!(:unrelated_project) { create(:project,  namespace: create(:user).namespace, creator_id: user2.id) }

      before :each do |each|
        fork_project.team << [user2, :reporters]
      end

      it "should return merge_request" do
        post api("/projects/#{fork_project.id}/merge_requests", user2),
          title: 'Test merge_request', source_branch: "feature_conflict", target_branch: "master",
          author: user2, target_project_id: project.id, description: 'Test description for Test merge_request'
        expect(response.status).to eq(201)
        expect(json_response['title']).to eq('Test merge_request')
        expect(json_response['description']).to eq('Test description for Test merge_request')
      end

      it "should not return 422 when source_branch equals target_branch" do
        expect(project.id).not_to eq(fork_project.id)
        expect(fork_project.forked?).to be_truthy
        expect(fork_project.forked_from_project).to eq(project)
        post api("/projects/#{fork_project.id}/merge_requests", user2),
        title: 'Test merge_request', source_branch: "master", target_branch: "master", author: user2, target_project_id: project.id
        expect(response.status).to eq(201)
        expect(json_response['title']).to eq('Test merge_request')
      end

      it "should return 400 when source_branch is missing" do
        post api("/projects/#{fork_project.id}/merge_requests", user2),
        title: 'Test merge_request', target_branch: "master", author: user2, target_project_id: project.id
        expect(response.status).to eq(400)
      end

      it "should return 400 when target_branch is missing" do
        post api("/projects/#{fork_project.id}/merge_requests", user2),
        title: 'Test merge_request', target_branch: "master", author: user2, target_project_id: project.id
        expect(response.status).to eq(400)
      end

      it "should return 400 when title is missing" do
        post api("/projects/#{fork_project.id}/merge_requests", user2),
        target_branch: 'master', source_branch: 'markdown', author: user2, target_project_id: project.id
        expect(response.status).to eq(400)
      end

      context 'when target_branch is specified' do
        it 'should return 422 if not a forked project' do
          post api("/projects/#{project.id}/merge_requests", user),
               title: 'Test merge_request',
               target_branch: 'master',
               source_branch: 'markdown',
               author: user,
               target_project_id: fork_project.id
          expect(response.status).to eq(422)
        end

        it 'should return 422 if targeting a different fork' do
          post api("/projects/#{fork_project.id}/merge_requests", user2),
               title: 'Test merge_request',
               target_branch: 'master',
               source_branch: 'markdown',
               author: user2,
               target_project_id: unrelated_project.id
          expect(response.status).to eq(422)
        end
      end

      it "should return 201 when target_branch is specified and for the same project" do
        post api("/projects/#{fork_project.id}/merge_requests", user2),
        title: 'Test merge_request', target_branch: 'master', source_branch: 'markdown', author: user2, target_project_id: fork_project.id
        expect(response.status).to eq(201)
      end
    end
  end

  describe "DELETE /projects/:id/merge_requests/:merge_request_id" do
    context "when the user is developer" do
      let(:developer) { create(:user) }

      before do
        project.team << [developer, :developer]
      end

      it "denies the deletion of the merge request" do
        delete api("/projects/#{project.id}/merge_requests/#{merge_request.id}", developer)
        expect(response.status).to be(403)
      end
    end

    context "when the user is project owner" do
      it "destroys the merge request owners can destroy" do
        delete api("/projects/#{project.id}/merge_requests/#{merge_request.id}", user)

        expect(response.status).to eq(200)
      end
    end
  end

  describe "PUT /projects/:id/merge_requests/:merge_request_id to close MR" do
    it "should return merge_request" do
      put api("/projects/#{project.id}/merge_requests/#{merge_request.id}", user), state_event: "close"
      expect(response.status).to eq(200)
      expect(json_response['state']).to eq('closed')
    end
  end

  describe "PUT /projects/:id/merge_requests/:merge_request_id/merge" do
    let(:pipeline) { create(:ci_pipeline_without_jobs) }

    it "should return merge_request in case of success" do
      put api("/projects/#{project.id}/merge_requests/#{merge_request.id}/merge", user)

      expect(response.status).to eq(200)
    end

    it "should return 406 if branch can't be merged" do
      allow_any_instance_of(MergeRequest).
        to receive(:can_be_merged?).and_return(false)

      put api("/projects/#{project.id}/merge_requests/#{merge_request.id}/merge", user)

      expect(response.status).to eq(406)
      expect(json_response['message']).to eq('Branch cannot be merged')
    end

    it "should return 405 if merge_request is not open" do
      merge_request.close
      put api("/projects/#{project.id}/merge_requests/#{merge_request.id}/merge", user)
      expect(response.status).to eq(405)
      expect(json_response['message']).to eq('405 Method Not Allowed')
    end

    it "should return 405 if merge_request is a work in progress" do
      merge_request.update_attribute(:title, "WIP: #{merge_request.title}")
      put api("/projects/#{project.id}/merge_requests/#{merge_request.id}/merge", user)
      expect(response.status).to eq(405)
      expect(json_response['message']).to eq('405 Method Not Allowed')
    end

    it 'returns 405 if the build failed for a merge request that requires success' do
      allow_any_instance_of(MergeRequest).to receive(:mergeable_ci_state?).and_return(false)

      put api("/projects/#{project.id}/merge_requests/#{merge_request.id}/merge", user)

      expect(response.status).to eq(405)
      expect(json_response['message']).to eq('405 Method Not Allowed')
    end

    it "should return 401 if user has no permissions to merge" do
      user2 = create(:user)
      project.team << [user2, :reporter]
      put api("/projects/#{project.id}/merge_requests/#{merge_request.id}/merge", user2)
      expect(response.status).to eq(401)
      expect(json_response['message']).to eq('401 Unauthorized')
    end

    it "returns 409 if the SHA parameter doesn't match" do
      put api("/projects/#{project.id}/merge_requests/#{merge_request.id}/merge", user), sha: merge_request.source_sha.succ

      expect(response.status).to eq(409)
      expect(json_response['message']).to start_with('SHA does not match HEAD of source branch')
    end

    it "succeeds if the SHA parameter matches" do
      put api("/projects/#{project.id}/merge_requests/#{merge_request.id}/merge", user), sha: merge_request.source_sha

      expect(response.status).to eq(200)
    end

    it "enables merge when build succeeds if the ci is active" do
      allow_any_instance_of(MergeRequest).to receive(:pipeline).and_return(pipeline)
      allow(pipeline).to receive(:active?).and_return(true)

      put api("/projects/#{project.id}/merge_requests/#{merge_request.id}/merge", user), merge_when_build_succeeds: true

      expect(response.status).to eq(200)
      expect(json_response['title']).to eq('Test')
      expect(json_response['merge_when_build_succeeds']).to eq(true)
    end
  end

  describe "PUT /projects/:id/merge_requests/:merge_request_id" do
    it "updates title and returns merge_request" do
      put api("/projects/#{project.id}/merge_requests/#{merge_request.id}", user), title: "New title"
      expect(response.status).to eq(200)
      expect(json_response['title']).to eq('New title')
    end

    it "updates description and returns merge_request" do
      put api("/projects/#{project.id}/merge_requests/#{merge_request.id}", user), description: "New description"
      expect(response.status).to eq(200)
      expect(json_response['description']).to eq('New description')
    end

    it "updates milestone_id and returns merge_request" do
      put api("/projects/#{project.id}/merge_requests/#{merge_request.id}", user), milestone_id: milestone.id
      expect(response.status).to eq(200)
      expect(json_response['milestone']['id']).to eq(milestone.id)
    end

    it "should return 400 when source_branch is specified" do
      put api("/projects/#{project.id}/merge_requests/#{merge_request.id}", user),
      source_branch: "master", target_branch: "master"
      expect(response.status).to eq(400)
    end

    it "should return merge_request with renamed target_branch" do
      put api("/projects/#{project.id}/merge_requests/#{merge_request.id}", user), target_branch: "wiki"
      expect(response.status).to eq(200)
      expect(json_response['target_branch']).to eq('wiki')
    end

    it 'should return 400 on invalid label names' do
      put api("/projects/#{project.id}/merge_requests/#{merge_request.id}",
              user),
          title: 'new issue',
          labels: 'label, ?'
      expect(response.status).to eq(400)
      expect(json_response['message']['labels']['?']['title']).to eq(['is invalid'])
    end
  end

  describe "POST /projects/:id/merge_requests/:merge_request_id/comments" do
    it "should return comment" do
      original_count = merge_request.notes.size

      post api("/projects/#{project.id}/merge_requests/#{merge_request.id}/comments", user), note: "My comment"
      expect(response.status).to eq(201)
      expect(json_response['note']).to eq('My comment')
      expect(json_response['author']['name']).to eq(user.name)
      expect(json_response['author']['username']).to eq(user.username)
      expect(merge_request.notes.size).to eq(original_count + 1)
    end

    it "should return 400 if note is missing" do
      post api("/projects/#{project.id}/merge_requests/#{merge_request.id}/comments", user)
      expect(response.status).to eq(400)
    end

    it "should return 404 if note is attached to non existent merge request" do
      post api("/projects/#{project.id}/merge_requests/404/comments", user),
           note: 'My comment'
      expect(response.status).to eq(404)
    end
  end

  describe "GET :id/merge_requests/:merge_request_id/comments" do
    it "should return merge_request comments ordered by created_at" do
      get api("/projects/#{project.id}/merge_requests/#{merge_request.id}/comments", user)
      expect(response.status).to eq(200)
      expect(json_response).to be_an Array
      expect(json_response.length).to eq(2)
      expect(json_response.first['note']).to eq("a comment on a MR")
      expect(json_response.first['author']['id']).to eq(user.id)
      expect(json_response.last['note']).to eq("another comment on a MR")
    end

    it "should return a 404 error if merge_request_id not found" do
      get api("/projects/#{project.id}/merge_requests/999/comments", user)
      expect(response.status).to eq(404)
    end
  end

  describe 'GET :id/merge_requests/:merge_request_id/closes_issues' do
    it 'returns the issue that will be closed on merge' do
      issue = create(:issue, project: project)
      mr = merge_request.tap do |mr|
        mr.update_attribute(:description, "Closes #{issue.to_reference(mr.project)}")
      end

      get api("/projects/#{project.id}/merge_requests/#{mr.id}/closes_issues", user)
      expect(response.status).to eq(200)
      expect(json_response).to be_an Array
      expect(json_response.length).to eq(1)
      expect(json_response.first['id']).to eq(issue.id)
    end

    it 'returns an empty array when there are no issues to be closed' do
      get api("/projects/#{project.id}/merge_requests/#{merge_request.id}/closes_issues", user)
      expect(response.status).to eq(200)
      expect(json_response).to be_an Array
      expect(json_response.length).to eq(0)
    end

    it 'handles external issues' do
      jira_project = create(:jira_project, :public, name: 'JIR_EXT1')
      issue = ExternalIssue.new("#{jira_project.name}-123", jira_project)
      merge_request = create(:merge_request, :simple, author: user, assignee: user, source_project: jira_project)
      merge_request.update_attribute(:description, "Closes #{issue.to_reference(jira_project)}")

      get api("/projects/#{jira_project.id}/merge_requests/#{merge_request.id}/closes_issues", user)

      expect(response.status).to eq(200)
      expect(json_response).to be_an Array
      expect(json_response.length).to eq(1)
      expect(json_response.first['title']).to eq(issue.title)
      expect(json_response.first['id']).to eq(issue.id)
    end
  end

  describe 'POST :id/merge_requests/:merge_request_id/subscription' do
    it 'subscribes to a merge request' do
      post api("/projects/#{project.id}/merge_requests/#{merge_request.id}/subscription", admin)

      expect(response.status).to eq(201)
      expect(json_response['subscribed']).to eq(true)
    end

    it 'returns 304 if already subscribed' do
      post api("/projects/#{project.id}/merge_requests/#{merge_request.id}/subscription", user)

      expect(response.status).to eq(304)
    end

    it 'returns 404 if the merge request is not found' do
      post api("/projects/#{project.id}/merge_requests/123/subscription", user)

      expect(response.status).to eq(404)
    end
  end

  describe 'DELETE :id/merge_requests/:merge_request_id/subscription' do
    it 'unsubscribes from a merge request' do
      delete api("/projects/#{project.id}/merge_requests/#{merge_request.id}/subscription", user)

      expect(response.status).to eq(200)
      expect(json_response['subscribed']).to eq(false)
    end

    it 'returns 304 if not subscribed' do
      delete api("/projects/#{project.id}/merge_requests/#{merge_request.id}/subscription", admin)

      expect(response.status).to eq(304)
    end

    it 'returns 404 if the merge request is not found' do
      post api("/projects/#{project.id}/merge_requests/123/subscription", user)

      expect(response.status).to eq(404)
    end
  end

  def mr_with_later_created_and_updated_at_time
    merge_request
    merge_request.created_at += 1.hour
    merge_request.updated_at += 30.minutes
    merge_request.save
    merge_request
  end

  def mr_with_earlier_created_and_updated_at_time
    merge_request_closed
    merge_request_closed.created_at -= 1.hour
    merge_request_closed.updated_at -= 30.minutes
    merge_request_closed.save
    merge_request_closed
  end
end
