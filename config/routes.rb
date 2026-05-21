# frozen_string_literal: true

CoreDataConnector::OpenGeographies::Engine.routes.draw do
  get ':project/places', to: 'places#index'
  get ':project/places/:slug', to: 'places#show'
  get ':project/tours/:slug', to: 'tours#show'
end
