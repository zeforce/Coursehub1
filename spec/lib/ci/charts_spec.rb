require 'spec_helper'

describe Ci::Charts, lib: true do

  context "build_times" do
    before do
      @pipeline = FactoryGirl.create(:ci_pipeline)
      FactoryGirl.create(:ci_build, pipeline: @pipeline)
    end

    it 'should return build times in minutes' do
      chart = Ci::Charts::BuildTime.new(@pipeline.project)
      expect(chart.build_times).to eq([2])
    end

    it 'should handle nil build times' do
      create(:ci_pipeline, duration: nil, project: @pipeline.project)

      chart = Ci::Charts::BuildTime.new(@pipeline.project)
      expect(chart.build_times).to eq([2, 0])
    end
  end
end
