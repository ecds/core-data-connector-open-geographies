FactoryBot.define do
  factory :place_name, class: "CoreDataConnector::PlaceName" do
    name { Faker::Address.city }
  end
end
