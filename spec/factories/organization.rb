# frozen_string_literal: true

FactoryBot.define do
  factory :organization, class: 'CoreDataConnector::Organization' do
    project_model factory: :place_model

    transient do
      name { Faker::Company.unique.name }
    end

    after(:build) do |organization, evaluator|
      organization.organization_names << CoreDataConnector::OrganizationName.new(name: evaluator.name, primary: true)
    end
  end
end
