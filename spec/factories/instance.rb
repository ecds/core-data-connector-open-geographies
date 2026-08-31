# frozen_string_literal: true

FactoryBot.define do
  factory :instance, class: 'CoreDataConnector::Instance' do
    project_model factory: :place_model

    transient do
      name { Faker::Book.unique.title }
    end

    after(:build) do |instance, evaluator|
      instance.source_names << CoreDataConnector::SourceName.new(name: evaluator.name, primary: true)
    end
  end
end
