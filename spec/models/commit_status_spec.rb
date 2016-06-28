require 'spec_helper'

describe CommitStatus, models: true do
  let(:project) { create(:project) }

  let(:pipeline) do
    create(:ci_pipeline, project: project, sha: project.commit.id)
  end

  let(:commit_status) { create(:commit_status, pipeline: pipeline) }

  it { is_expected.to belong_to(:pipeline) }
  it { is_expected.to belong_to(:user) }
  it { is_expected.to belong_to(:project) }

  it { is_expected.to validate_presence_of(:name) }
  it { is_expected.to validate_inclusion_of(:status).in_array(%w(pending running failed success canceled)) }

  it { is_expected.to delegate_method(:sha).to(:pipeline) }
  it { is_expected.to delegate_method(:short_sha).to(:pipeline) }

  it { is_expected.to respond_to :success? }
  it { is_expected.to respond_to :failed? }
  it { is_expected.to respond_to :running? }
  it { is_expected.to respond_to :pending? }

  describe :author do
    subject { commit_status.author }
    before { commit_status.author = User.new }

    it { is_expected.to eq(commit_status.user) }
  end

  describe :started? do
    subject { commit_status.started? }

    context 'without started_at' do
      before { commit_status.started_at = nil }

      it { is_expected.to be_falsey }
    end

    %w(running success failed).each do |status|
      context "if commit status is #{status}" do
        before { commit_status.status = status }

        it { is_expected.to be_truthy }
      end
    end

    %w(pending canceled).each do |status|
      context "if commit status is #{status}" do
        before { commit_status.status = status }

        it { is_expected.to be_falsey }
      end
    end
  end

  describe :active? do
    subject { commit_status.active? }

    %w(pending running).each do |state|
      context "if commit_status.status is #{state}" do
        before { commit_status.status = state }

        it { is_expected.to be_truthy }
      end
    end

    %w(success failed canceled).each do |state|
      context "if commit_status.status is #{state}" do
        before { commit_status.status = state }

        it { is_expected.to be_falsey }
      end
    end
  end

  describe :complete? do
    subject { commit_status.complete? }

    %w(success failed canceled).each do |state|
      context "if commit_status.status is #{state}" do
        before { commit_status.status = state }

        it { is_expected.to be_truthy }
      end
    end

    %w(pending running).each do |state|
      context "if commit_status.status is #{state}" do
        before { commit_status.status = state }

        it { is_expected.to be_falsey }
      end
    end
  end

  describe :duration do
    subject { commit_status.duration }

    it { is_expected.to eq(120.0) }

    context 'if the building process has not started yet' do
      before do
        commit_status.started_at = nil
        commit_status.finished_at = nil
      end

      it { is_expected.to be_nil }
    end

    context 'if the building process has started' do
      before do
        commit_status.started_at = Time.now - 1.minute
        commit_status.finished_at = nil
      end

      it { is_expected.to be_a(Float) }
      it { is_expected.to be > 0.0 }
    end
  end

  describe :latest do
    subject { CommitStatus.latest.order(:id) }

    before do
      @commit1 = FactoryGirl.create :commit_status, pipeline: pipeline, name: 'aa', ref: 'bb', status: 'running'
      @commit2 = FactoryGirl.create :commit_status, pipeline: pipeline, name: 'cc', ref: 'cc', status: 'pending'
      @commit3 = FactoryGirl.create :commit_status, pipeline: pipeline, name: 'aa', ref: 'cc', status: 'success'
      @commit4 = FactoryGirl.create :commit_status, pipeline: pipeline, name: 'cc', ref: 'bb', status: 'success'
      @commit5 = FactoryGirl.create :commit_status, pipeline: pipeline, name: 'aa', ref: 'bb', status: 'success'
    end

    it 'return unique statuses' do
      is_expected.to eq([@commit4, @commit5])
    end
  end

  describe :running_or_pending do
    subject { CommitStatus.running_or_pending.order(:id) }

    before do
      @commit1 = FactoryGirl.create :commit_status, pipeline: pipeline, name: 'aa', ref: 'bb', status: 'running'
      @commit2 = FactoryGirl.create :commit_status, pipeline: pipeline, name: 'cc', ref: 'cc', status: 'pending'
      @commit3 = FactoryGirl.create :commit_status, pipeline: pipeline, name: 'aa', ref: nil, status: 'success'
      @commit4 = FactoryGirl.create :commit_status, pipeline: pipeline, name: 'dd', ref: nil, status: 'failed'
      @commit5 = FactoryGirl.create :commit_status, pipeline: pipeline, name: 'ee', ref: nil, status: 'canceled'
    end

    it 'return statuses that are running or pending' do
      is_expected.to eq([@commit1, @commit2])
    end
  end

  describe '#before_sha' do
    subject { commit_status.before_sha }

    context 'when no before_sha is set for pipeline' do
      before { pipeline.before_sha = nil }

      it 'return blank sha' do
        is_expected.to eq(Gitlab::Git::BLANK_SHA)
      end
    end

    context 'for before_sha set for pipeline' do
      let(:value) { '1234' }
      before { pipeline.before_sha = value }

      it 'return the set value' do
        is_expected.to eq(value)
      end
    end
  end

  describe '#stages' do
    before do
      FactoryGirl.create :commit_status, pipeline: pipeline, stage: 'build', stage_idx: 0, status: 'success'
      FactoryGirl.create :commit_status, pipeline: pipeline, stage: 'build', stage_idx: 0, status: 'failed'
      FactoryGirl.create :commit_status, pipeline: pipeline, stage: 'deploy', stage_idx: 2, status: 'running'
      FactoryGirl.create :commit_status, pipeline: pipeline, stage: 'test', stage_idx: 1, status: 'success'
    end

    context 'stages list' do
      subject { CommitStatus.where(pipeline: pipeline).stages }

      it 'return ordered list of stages' do
        is_expected.to eq(%w(build test deploy))
      end
    end

    context 'stages with statuses' do
      subject { CommitStatus.where(pipeline: pipeline).stages_status }

      it 'return list of stages with statuses' do
        is_expected.to eq({
          'build' => 'failed',
          'test' => 'success',
          'deploy' => 'running'
        })
      end
    end
  end

  describe '#commit' do
    it 'returns commit pipeline has been created for' do
      expect(commit_status.commit).to eq project.commit
    end
  end
end
