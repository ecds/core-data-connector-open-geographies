FactoryBot.define do
  factory :place, class: "CoreDataConnector::Place" do
    user_defined {
      {
        Faker::Internet.unique.uuid => "Description"
      }
    }
  end
end
