# frozen_string_literal: true

module CoreDataConnector
  module OpenGeographies
    module V1
      class Place < ::CoreDataConnector::Place
        include Searchable

        searchable_index 'open_geographies_v1'

        self.table_name = 'core_data_connector_places'

        def extras
          return {} unless place_geometry&.geometry

          center = centroid
          return {} unless center

          lat = center['lat'].to_f
          lon = center['lon'].to_f

          {
            geo: { point: { lat:, lon: } },
            administrative_area: ::CoreDataConnector::OpenGeographies::GeonamesHierarchy.lookup(place_id: id, lat:, lng: lon),
          }
        end

        private

        # SQL, not RGeo, computes this: geometry isn't always a bare Point (some
        # records store a GeometryCollection), and RGeo's GEOS binding here
        # doesn't expose a Ruby-level #centroid at all (raises NoMethodError) -
        # only PostGIS's ST_Centroid reliably handles arbitrary geometry types,
        # which is exactly why CoreDataConnector::Place.centroid_function
        # computes this in SQL rather than Ruby too.
        def centroid
          ::CoreDataConnector::PlaceGeometry.connection.select_one(
            ::CoreDataConnector::PlaceGeometry.sanitize_sql_array([
              'SELECT ST_Y(ST_Centroid(geometry)) AS lat, ST_X(ST_Centroid(geometry)) AS lon ' \
                'FROM core_data_connector_place_geometries WHERE id = ?',
              place_geometry.id,
            ]),
          )
        end
      end
    end
  end
end
