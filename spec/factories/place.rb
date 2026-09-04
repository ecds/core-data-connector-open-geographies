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

    # The vendored CoreDataConnector (see bin/sync_core_data_connector) added
    # save-time callbacks (Auditable, Publishable, ...) that weren't in the
    # old gem this factory was written against, and at least one of them
    # touches the record's own `primary_name` (a has_one) *during* the
    # parent's own save - before the after(:build)-appended place_names
    # entry above has actually been persisted - which permanently caches
    # primary_name (and so #name, which delegates to it) as nil regardless
    # of the row that really exists in place_names afterward. Can't just
    # move the name-creation to after(:create) instead - Nameable#validate_names
    # requires a primary name to already exist at the parent's own initial
    # save, which is exactly why it's still built (not created) above.
    # Reloading once creation is fully done busts every association cache
    # (including the wrongly-nil primary_name) without caring which
    # vendored callback caused it or when.
    after(:create, &:reload)
  end
end
