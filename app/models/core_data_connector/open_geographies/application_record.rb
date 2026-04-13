module CoreDataConnector
  module OpenGeographies
    class ApplicationRecord < ActiveRecord::Base
      self.abstract_class = true
    end
  end
end
