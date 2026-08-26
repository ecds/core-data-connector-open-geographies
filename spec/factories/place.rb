# frozen_string_literal: true

FactoryBot.define do
  factory :place, class: 'CoreDataConnector::Place' do
    user_defined do
      {
        Faker::Internet.unique.uuid => 'Description',
      }
    end
  end
end
