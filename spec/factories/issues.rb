FactoryGirl.define do
  factory :issue do
    title
    author
    project

    trait :confidential do
      confidential true
    end

    trait :closed do
      state :closed
    end

    trait :reopened do
      state :reopened
    end

    factory :closed_issue, traits: [:closed]
    factory :reopened_issue, traits: [:reopened]
  end
end
