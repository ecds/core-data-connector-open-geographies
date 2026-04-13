Rails.application.routes.draw do
  mount CoreDataConnector::OpenGeographies::Engine, at: '/open_geographies'
end
