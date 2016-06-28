FactoryGirl.define do
  factory :commit_status, class: CommitStatus do
    name 'default'
    status 'success'
    description 'commit status'
    pipeline factory: :ci_pipeline_with_one_job
    started_at 'Tue, 26 Jan 2016 08:21:42 +0100'
    finished_at 'Tue, 26 Jan 2016 08:23:42 +0100'

    after(:build) do |build, evaluator|
      build.project = build.pipeline.project
    end

    factory :generic_commit_status, class: GenericCommitStatus do
      name 'generic'
      description 'external commit status'
    end
  end
end
