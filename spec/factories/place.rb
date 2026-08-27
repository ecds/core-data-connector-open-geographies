# frozen_string_literal: true

FactoryBot.define do
  factory :place, class: 'CoreDataConnector::Place' do
    user_defined do
      {
        Faker::Internet.unique.uuid => 'Description',
      }
    end

    # A Place needs a primary PlaceName to pass validation (Nameable#validate_names) -
    # without this, create(:place, ...) fails, which nothing caught before since the
    # only existing usage was build(:place, ...), never create.
    transient do
      name { Faker::Address.unique.city }
    end

    after(:build) do |place, evaluator|
      place.place_names << CoreDataConnector::PlaceName.new(name: evaluator.name, primary: true)
    end
  end
end
