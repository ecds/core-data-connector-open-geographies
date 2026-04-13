module CoreDataConnector
  module OpenGeographies
    class Engine < ::Rails::Engine
      require "rails/all"
      isolate_namespace CoreDataConnector::OpenGeographies
    end
  end
end
