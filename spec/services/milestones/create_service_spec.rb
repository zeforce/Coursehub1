require 'spec_helper'

describe Milestones::CreateService, services: true do
  let(:project) { create(:empty_project) }
  let(:user) { create(:user) }

  describe :execute do
    context "valid params" do
      before do
        project.team << [user, :master]

        opts = {
          title: 'v2.1.9',
          description: 'Patch release to fix security issue'
        }

        @milestone = Milestones::CreateService.new(project, user, opts).execute
      end

      it { expect(@milestone).to be_valid }
      it { expect(@milestone.title).to eq('v2.1.9') }
    end
  end
end
