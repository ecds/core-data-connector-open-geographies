FactoryBot.define do
  factory :project, class: "CoreDataConnector::Project" do
    name { Faker::Name.unique.name }

    # after(:create) do |project, evaluator|
    #   create(:place_model)
    # end
  end
end
