require 'spec_helper'

describe API::API, api: true  do
  include ApiHelpers
  let(:user)            { create(:user) }
  let!(:project)        { create(:project) }
  let(:issue)           { create(:issue, project: project, author: user) }
  let!(:award_emoji)    { create(:award_emoji, awardable: issue, user: user) }
  let!(:merge_request)  { create(:merge_request, source_project: project, target_project: project) }
  let!(:downvote)       { create(:award_emoji, :downvote, awardable: merge_request, user: user) }
  let!(:note)           { create(:note, project: project, noteable: issue) }

  before { project.team << [user, :master] }

  describe "GET /projects/:id/awardable/:awardable_id/award_emoji" do
    context 'on an issue' do
      it "returns an array of award_emoji" do
        get api("/projects/#{project.id}/issues/#{issue.id}/award_emoji", user)

        expect(response.status).to eq(200)
        expect(json_response).to be_an Array
        expect(json_response.first['name']).to eq(award_emoji.name)
      end

      it "should return a 404 error when issue id not found" do
        get api("/projects/#{project.id}/issues/12345/award_emoji", user)

        expect(response.status).to eq(404)
      end
    end

    context 'on a merge request' do
      it "returns an array of award_emoji" do
        get api("/projects/#{project.id}/merge_requests/#{merge_request.id}/award_emoji", user)

        expect(response.status).to eq(200)
        expect(json_response).to be_an Array
        expect(json_response.first['name']).to eq(downvote.name)
      end
    end

    context 'when the user has no access' do
      it 'returns a status code 404' do
        user1 = create(:user)

        get api("/projects/#{project.id}/merge_requests/#{merge_request.id}/award_emoji", user1)

        expect(response.status).to eq(404)
      end
    end
  end

  describe 'GET /projects/:id/awardable/:awardable_id/notes/:note_id/award_emoji' do
    let!(:rocket)  { create(:award_emoji, awardable: note, name: 'rocket') }

    it 'returns an array of award emoji' do
      get api("/projects/#{project.id}/issues/#{issue.id}/notes/#{note.id}/award_emoji", user)

      expect(response.status).to eq(200)
      expect(json_response).to be_an Array
      expect(json_response.first['name']).to eq(rocket.name)
    end
  end


  describe "GET /projects/:id/awardable/:awardable_id/award_emoji/:award_id" do
    context 'on an issue' do
      it "returns the award emoji" do
        get api("/projects/#{project.id}/issues/#{issue.id}/award_emoji/#{award_emoji.id}", user)

        expect(response.status).to eq(200)
        expect(json_response['name']).to eq(award_emoji.name)
        expect(json_response['awardable_id']).to eq(issue.id)
        expect(json_response['awardable_type']).to eq("Issue")
      end

      it "returns a 404 error if the award is not found" do
        get api("/projects/#{project.id}/issues/#{issue.id}/award_emoji/12345", user)

        expect(response.status).to eq(404)
      end
    end

    context 'on a merge request' do
      it 'returns the award emoji' do
        get api("/projects/#{project.id}/merge_requests/#{merge_request.id}/award_emoji/#{downvote.id}", user)

        expect(response.status).to eq(200)
        expect(json_response['name']).to eq(downvote.name)
        expect(json_response['awardable_id']).to eq(merge_request.id)
        expect(json_response['awardable_type']).to eq("MergeRequest")
      end
    end

    context 'when the user has no access' do
      it 'returns a status code 404' do
        user1 = create(:user)

        get api("/projects/#{project.id}/merge_requests/#{merge_request.id}/award_emoji/#{downvote.id}", user1)

        expect(response.status).to eq(404)
      end
    end
  end

  describe 'GET /projects/:id/awardable/:awardable_id/notes/:note_id/award_emoji/:award_id' do
    let!(:rocket)  { create(:award_emoji, awardable: note, name: 'rocket') }

    it 'returns an award emoji' do
      get api("/projects/#{project.id}/issues/#{issue.id}/notes/#{note.id}/award_emoji/#{rocket.id}", user)

      expect(response.status).to eq(200)
      expect(json_response).not_to be_an Array
      expect(json_response['name']).to eq(rocket.name)
    end
  end

  describe "POST /projects/:id/awardable/:awardable_id/award_emoji" do
    context "on an issue" do
      it "creates a new award emoji" do
        post api("/projects/#{project.id}/issues/#{issue.id}/award_emoji", user), name: 'blowfish'

        expect(response.status).to eq(201)
        expect(json_response['name']).to eq('blowfish')
        expect(json_response['user']['username']).to eq(user.username)
      end

      it "should return a 400 bad request error if the name is not given" do
        post api("/projects/#{project.id}/issues/#{issue.id}/award_emoji", user)

        expect(response.status).to eq(400)
      end

      it "should return a 401 unauthorized error if the user is not authenticated" do
        post api("/projects/#{project.id}/issues/#{issue.id}/award_emoji"), name: 'thumbsup'

        expect(response.status).to eq(401)
      end
    end
  end

  describe "POST /projects/:id/awardable/:awardable_id/notes/:note_id/award_emoji" do
    it 'creates a new award emoji' do
      expect do
        post api("/projects/#{project.id}/issues/#{issue.id}/notes/#{note.id}/award_emoji", user), name: 'rocket'
      end.to change { note.award_emoji.count }.from(0).to(1)

      expect(response.status).to eq(201)
      expect(json_response['user']['username']).to eq(user.username)
    end
  end

  describe 'DELETE /projects/:id/awardable/:awardable_id/award_emoji/:award_id' do
    context 'when the awardable is an Issue' do
      it 'deletes the award' do
        expect do
          delete api("/projects/#{project.id}/issues/#{issue.id}/award_emoji/#{award_emoji.id}", user)
        end.to change { issue.award_emoji.count }.from(1).to(0)

        expect(response.status).to eq(200)
      end

      it 'returns a 404 error when the award emoji can not be found' do
        delete api("/projects/#{project.id}/issues/#{issue.id}/award_emoji/12345", user)

        expect(response.status).to eq(404)
      end
    end

    context 'when the awardable is a Merge Request' do
      it 'deletes the award' do
        expect do
          delete api("/projects/#{project.id}/merge_requests/#{merge_request.id}/award_emoji/#{downvote.id}", user)
        end.to change { merge_request.award_emoji.count }.from(1).to(0)

        expect(response.status).to eq(200)
      end

      it 'returns a 404 error when note id not found' do
        delete api("/projects/#{project.id}/merge_requests/#{merge_request.id}/notes/12345", user)

        expect(response.status).to eq(404)
      end
    end
  end

  describe 'DELETE /projects/:id/awardable/:awardable_id/award_emoji/:award_emoji_id' do
    let!(:rocket)  { create(:award_emoji, awardable: note, name: 'rocket', user: user) }

    it 'deletes the award' do
      expect do
        delete api("/projects/#{project.id}/issues/#{issue.id}/notes/#{note.id}/award_emoji/#{rocket.id}", user)
      end.to change { note.award_emoji.count }.from(1).to(0)

      expect(response.status).to eq(200)
    end
  end
end
