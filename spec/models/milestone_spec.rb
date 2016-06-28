require 'spec_helper'

describe Milestone, models: true do
  describe "Associations" do
    it { is_expected.to belong_to(:project) }
    it { is_expected.to have_many(:issues) }
  end

  describe "Validation" do
    before do
      allow(subject).to receive(:set_iid).and_return(false)
    end

    it { is_expected.to validate_presence_of(:title) }
    it { is_expected.to validate_presence_of(:project) }
  end

  let(:milestone) { create(:milestone) }
  let(:issue) { create(:issue) }
  let(:user) { create(:user) }

  describe "#title" do
    let(:milestone) { create(:milestone, title: "<b>test</b>") }

    it "sanitizes title" do
      expect(milestone.title).to eq("test")
    end
  end

  describe "unique milestone title per project" do
    it "shouldn't accept the same title in a project twice" do
      new_milestone = Milestone.new(project: milestone.project, title: milestone.title)
      expect(new_milestone).not_to be_valid
    end

    it "should accept the same title in another project" do
      project = build(:project)
      new_milestone = Milestone.new(project: project, title: milestone.title)

      expect(new_milestone).to be_valid
    end
  end

  describe "#percent_complete" do
    it "should not count open issues" do
      milestone.issues << issue
      expect(milestone.percent_complete(user)).to eq(0)
    end

    it "should count closed issues" do
      issue.close
      milestone.issues << issue
      expect(milestone.percent_complete(user)).to eq(100)
    end

    it "should recover from dividing by zero" do
      expect(milestone.percent_complete(user)).to eq(0)
    end
  end

  describe "#expires_at" do
    it "should be nil when due_date is unset" do
      milestone.update_attributes(due_date: nil)
      expect(milestone.expires_at).to be_nil
    end

    it "should not be nil when due_date is set" do
      milestone.update_attributes(due_date: Date.tomorrow)
      expect(milestone.expires_at).to be_present
    end
  end

  describe :expired? do
    context "expired" do
      before do
        allow(milestone).to receive(:due_date).and_return(Date.today.prev_year)
      end

      it { expect(milestone.expired?).to be_truthy }
    end

    context "not expired" do
      before do
        allow(milestone).to receive(:due_date).and_return(Date.today.next_year)
      end

      it { expect(milestone.expired?).to be_falsey }
    end
  end

  describe :percent_complete do
    before do
      allow(milestone).to receive_messages(
        closed_items_count: 3,
        total_items_count: 4
      )
    end

    it { expect(milestone.percent_complete(user)).to eq(75) }
  end

  describe :items_count do
    before do
      milestone.issues << create(:issue)
      milestone.issues << create(:closed_issue)
      milestone.merge_requests << create(:merge_request)
    end

    it { expect(milestone.closed_items_count(user)).to eq(1) }
    it { expect(milestone.total_items_count(user)).to eq(3) }
    it { expect(milestone.is_empty?(user)).to be_falsey }
  end

  describe :can_be_closed? do
    it { expect(milestone.can_be_closed?).to be_truthy }
  end

  describe :total_items_count do
    before do
      create :closed_issue, milestone: milestone
      create :merge_request, milestone: milestone
    end

    it 'Should return total count of issues and merge requests assigned to milestone' do
      expect(milestone.total_items_count(user)).to eq 2
    end
  end

  describe :can_be_closed? do
    before do
      milestone = create :milestone
      create :closed_issue, milestone: milestone

      create :issue
    end

    it 'should be true if milestone active and all nested issues closed' do
      expect(milestone.can_be_closed?).to be_truthy
    end

    it 'should be false if milestone active and not all nested issues closed' do
      issue.milestone = milestone
      issue.save

      expect(milestone.can_be_closed?).to be_falsey
    end
  end

  describe '#sort_issues' do
    let(:milestone) { create(:milestone) }

    let(:issue1) { create(:issue, milestone: milestone, position: 1) }
    let(:issue2) { create(:issue, milestone: milestone, position: 2) }
    let(:issue3) { create(:issue, milestone: milestone, position: 3) }
    let(:issue4) { create(:issue, position: 42) }

    it 'sorts the given issues' do
      milestone.sort_issues([issue3.id, issue2.id, issue1.id])

      issue1.reload
      issue2.reload
      issue3.reload

      expect(issue1.position).to eq(3)
      expect(issue2.position).to eq(2)
      expect(issue3.position).to eq(1)
    end

    it 'ignores issues not part of the milestone' do
      milestone.sort_issues([issue3.id, issue2.id, issue1.id, issue4.id])

      issue4.reload

      expect(issue4.position).to eq(42)
    end
  end

  describe '.search' do
    let(:milestone) { create(:milestone, title: 'foo', description: 'bar') }

    it 'returns milestones with a matching title' do
      expect(described_class.search(milestone.title)).to eq([milestone])
    end

    it 'returns milestones with a partially matching title' do
      expect(described_class.search(milestone.title[0..2])).to eq([milestone])
    end

    it 'returns milestones with a matching title regardless of the casing' do
      expect(described_class.search(milestone.title.upcase)).to eq([milestone])
    end

    it 'returns milestones with a matching description' do
      expect(described_class.search(milestone.description)).to eq([milestone])
    end

    it 'returns milestones with a partially matching description' do
      expect(described_class.search(milestone.description[0..2])).
        to eq([milestone])
    end

    it 'returns milestones with a matching description regardless of the casing' do
      expect(described_class.search(milestone.description.upcase)).
        to eq([milestone])
    end
  end

  describe '.upcoming_ids_by_projects' do
    let(:project_1) { create(:empty_project) }
    let(:project_2) { create(:empty_project) }
    let(:project_3) { create(:empty_project) }
    let(:projects) { [project_1, project_2, project_3] }

    let!(:past_milestone_project_1) { create(:milestone, project: project_1, due_date: Time.now - 1.day) }
    let!(:current_milestone_project_1) { create(:milestone, project: project_1, due_date: Time.now + 1.day) }
    let!(:future_milestone_project_1) { create(:milestone, project: project_1, due_date: Time.now + 2.days) }

    let!(:past_milestone_project_2) { create(:milestone, project: project_2, due_date: Time.now - 1.day) }
    let!(:closed_milestone_project_2) { create(:milestone, :closed, project: project_2, due_date: Time.now + 1.day) }
    let!(:current_milestone_project_2) { create(:milestone, project: project_2, due_date: Time.now + 2.days) }

    let!(:past_milestone_project_3) { create(:milestone, project: project_3, due_date: Time.now - 1.day) }

    # The call to `#try` is because this returns a relation with a Postgres DB,
    # and an array of IDs with a MySQL DB.
    let(:milestone_ids) { Milestone.upcoming_ids_by_projects(projects).map { |id| id.try(:id) || id } }

    it 'returns the next upcoming open milestone ID for each project' do
      expect(milestone_ids).to contain_exactly(current_milestone_project_1.id, current_milestone_project_2.id)
    end

    context 'when the projects have no open upcoming milestones' do
      let(:projects) { [project_3] }

      it 'returns no results' do
        expect(milestone_ids).to be_empty
      end
    end
  end
end
