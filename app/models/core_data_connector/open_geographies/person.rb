module CoreDataConnector
  module OpenGeographies
    class Person < ::CoreDataConnector::Person
      include Searchable

      self.table_name = "core_data_connector_people"
    end
  end
end
