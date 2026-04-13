CoreDataConnector::OpenGeographies::Engine.routes.draw do
  get ":project/places", to: "places#index"
  get ":project/places/:slug", to: "places#show"
end
