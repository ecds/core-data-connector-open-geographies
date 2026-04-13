module CoreDataConnector
  module OpenGeographies
    class Work < ::CoreDataConnector::Work
      include Searchable

      self.table_name = "core_data_connector_works"
    end
  end
end
