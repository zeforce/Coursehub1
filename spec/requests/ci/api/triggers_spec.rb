require 'spec_helper'

describe Ci::API::API do
  include ApiHelpers

  describe 'POST /projects/:project_id/refs/:ref/trigger' do
    let!(:trigger_token) { 'secure token' }
    let!(:project) { FactoryGirl.create(:project, ci_id: 10) }
    let!(:project2) { FactoryGirl.create(:empty_project, ci_id: 11) }
    let!(:trigger) { FactoryGirl.create(:ci_trigger, project: project, token: trigger_token) }
    let(:options) do
      {
        token: trigger_token
      }
    end

    before do
      stub_ci_pipeline_to_return_yaml_file
    end

    context 'Handles errors' do
      it 'should return bad request if token is missing' do
        post ci_api("/projects/#{project.ci_id}/refs/master/trigger")
        expect(response.status).to eq(400)
      end

      it 'should return not found if project is not found' do
        post ci_api('/projects/0/refs/master/trigger'), options
        expect(response.status).to eq(404)
      end

      it 'should return unauthorized if token is for different project' do
        post ci_api("/projects/#{project2.ci_id}/refs/master/trigger"), options
        expect(response.status).to eq(401)
      end
    end

    context 'Have a commit' do
      let(:pipeline) { project.pipelines.last }

      it 'should create builds' do
        post ci_api("/projects/#{project.ci_id}/refs/master/trigger"), options
        expect(response.status).to eq(201)
        pipeline.builds.reload
        expect(pipeline.builds.size).to eq(2)
      end

      it 'should return bad request with no builds created if there\'s no commit for that ref' do
        post ci_api("/projects/#{project.ci_id}/refs/other-branch/trigger"), options
        expect(response.status).to eq(400)
        expect(json_response['message']).to eq('No builds created')
      end

      context 'Validates variables' do
        let(:variables) do
          { 'TRIGGER_KEY' => 'TRIGGER_VALUE' }
        end

        it 'should validate variables to be a hash' do
          post ci_api("/projects/#{project.ci_id}/refs/master/trigger"), options.merge(variables: 'value')
          expect(response.status).to eq(400)
          expect(json_response['message']).to eq('variables needs to be a hash')
        end

        it 'should validate variables needs to be a map of key-valued strings' do
          post ci_api("/projects/#{project.ci_id}/refs/master/trigger"), options.merge(variables: { key: %w(1 2) })
          expect(response.status).to eq(400)
          expect(json_response['message']).to eq('variables needs to be a map of key-valued strings')
        end

        it 'create trigger request with variables' do
          post ci_api("/projects/#{project.ci_id}/refs/master/trigger"), options.merge(variables: variables)
          expect(response.status).to eq(201)
          pipeline.builds.reload
          expect(pipeline.builds.first.trigger_request.variables).to eq(variables)
        end
      end
    end
  end
end
