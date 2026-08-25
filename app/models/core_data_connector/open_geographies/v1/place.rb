# frozen_string_literal: true

module CoreDataConnector
  module OpenGeographies
    module V1
      class Place < ::CoreDataConnector::Place
        include Searchable

        self.table_name = 'core_data_connector_places'

        def extras
          return {} unless place_geometry&.geometry

          {
            geo: {
              point: { lat: place_geometry.geometry.y, lon: place_geometry.geometry.x },
            },
          }
        end
      end
    end
  end
end
