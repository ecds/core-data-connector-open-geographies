# frozen_string_literal: true

require 'rgeo/geo_json'

module CoreDataConnector
  module OpenGeographies
    module V1
      class Place < ::CoreDataConnector::Place
        include Searchable

        searchable_index 'open_geographies_v1'

        self.table_name = 'core_data_connector_places'

        class << self
          # Streams GeoJSON Features for every place in `project_model` -
          # for a bulk vector-tile pipeline (tippecanoe/pmtiles), not the ES
          # index (see #geojson_features for why this needs its own path
          # rather than reusing #extras/#search_data directly). Batched via
          # find_each so a multi-thousand-record atlas (Georgia Coast has
          # 5,000+) doesn't load every record into memory at once. Yields
          # each Feature if a block is given; otherwise returns an
          # Enumerator - `.to_a` that into a FeatureCollection, or stream it
          # straight into whatever builds the tiles. This engine owns the
          # data shape, deliberately not how it gets tiled or published -
          # see core-data-cloud's pmtiles pipeline for that.
          def each_geojson_feature(project_model, &block)
            return enum_for(:each_geojson_feature, project_model) unless block_given?

            where(project_model:).find_each do |place|
              place.geojson_features.each(&block)
            end
          end
        end

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

        # One GeoJSON Feature per underlying geometry, not per record: a
        # GeometryCollection (a non-contiguous record - Georgia Coast has
        # 1,766 of them, e.g. a barrier island's separate islets) explodes
        # into one Feature per member geometry, matching what a map
        # renderer actually wants - independent shapes, not one indivisible
        # multi-part blob a click can't distinguish. #extras only ever
        # computes a centroid point (right for a search-facing summary;
        # search doesn't need the actual shape), so this reads the real
        # geometry straight from place_geometry instead.
        #
        # Properties are a deliberately flat subset of #search_data (not the
        # full nested document - unlike an ES summary, a vector-tile
        # feature's properties should stay small) using the exact same
        # canonical field names/values as everywhere else in v1 - "follows
        # the OG schema" by construction, not by a second hand-maintained
        # mapping (compare core-data-cloud's pre-v1, GCA-specific
        # Ecds::Geojson, which hardcodes its own per-atlas UUID/
        # related_model_id property mapping - this is the generalized
        # replacement, any v1 atlas gets the same properties for free).
        def geojson_features
          return [] unless place_geometry&.geometry

          encoded = RGeo::GeoJSON.encode(place_geometry.geometry)
          geometries = encoded['type'] == 'GeometryCollection' ? encoded['geometries'] : [encoded]

          geometries.map do |geometry|
            { type: 'Feature', properties: geojson_properties, geometry: }
          end
        end

        private

        # Deliberately not #search_data: that calls #extras, which does a
        # live GeoNames HTTP lookup (GeonamesHierarchy.lookup) for any
        # record with no cached hierarchy yet - a few seconds' latency the
        # ES indexer happily pays once per record, but ruinous multiplied
        # across a bulk export of thousands (found live: a 10-record sample
        # against Georgia Coast Atlas didn't finish in two minutes). None of
        # these properties need administrative_area/geo anyway - the real
        # geometry comes from place_geometry directly, not the centroid
        # #extras computes for the ES index. #base_search_data alone is
        # cheap (local attribute reads only); #promoted_type_names below is
        # a direct, single-relationship query rather than the generic
        # #related walk, which would call #summarize - and so #extras - on
        # every *other* promoted relationship's related records too
        # (County, Map Layers, ... - several of Georgia Coast's own Places
        # relationships point at other Place records).
        def geojson_properties
          data = base_search_data
          {
            uuid: data[:uuid],
            slug: data[:slug],
            name: data[:name],
            model_type: data[:model_type],
            project: data[:project],
            types: promoted_type_names,
          }
        end

        def promoted_type_names
          types_relationship_name = PromotedRelationships.for(self).key(:types)
          return [] unless types_relationship_name

          rel = ::CoreDataConnector::ProjectModelRelationship.find_by(primary_model: project_model, name: types_relationship_name)
          return [] unless rel

          ::CoreDataConnector::Relationship.where(project_model_relationship: rel, primary_record: self).map { |r| r.related_record.name }
        end

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
