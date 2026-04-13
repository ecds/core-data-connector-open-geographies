require 'rgeo'
require 'rgeo/geo_json'

module Ecds
  class AddOsm
    attr_reader :osm_features, :geometry, :collection

    def initialize(place)
      @place = place
      @collection = []
      @geometry = nil
      @osm_features = nil
      @factory = RGeo::Geos.factory
      @point = Ecds::Helpers.find_point place.place_geometry.geometry
      @query = query
      @converter = Osmtogeojson.new(@query)
      core_data_geometries
      osm_geometries
      collect
    end

    def query_text
      @query.to_s
    end

    def feature_item
      @osm_features[:features].each do |feature|
        type = feature[:properties][:id].split('/').first
        user_defined = {
          "384cb567-6e57-4691-94a3-e196c198e9c6": type,
          "8f35ead2-fa02-4273-8c21-90fea494f362": feature[:properties].to_json
        }
        source_name = CoreDataConnector::SourceName.find_by(name: feature[:properties][:id], primary: true)
        if source_name.nil?
          item = CoreDataConnector::Item.new(
            project_model_id: 37,
            user_defined:
          )
          source_name = CoreDataConnector::SourceName.new(name: feature[:properties][:id], primary: true)
          item.source_names << source_name
          CoreDataConnector::Relationship.create(
            project_model_relationship_id: 57,
            primary_record: item,
            related_record: @place
          )
        else
          CoreDataConnector::Relationship.create_or_find_by(
            project_model_relationship_id: 57,
            primary_record: source_name.nameable,
            related_record: @place
          )
          source_name.nameable.update(user_defined:)
        end
      end
    end

    def place_geometry
      return if @collection.nil?

      @place.place_geometry.update(geometry: @geometry)
    end

    private

    def collect
      return if @collection.empty?

      lines_to_polygon

      @geometry = if @collection.count > 1
                    RGeo::Geos::CAPIGeometryCollectionImpl.create(@factory, [@collection].flatten)
                  else
                    @collection.first
                  end
    end

    def core_data_geometries
      place_geom = @place.place_geometry

      return nil unless place_geom.present?

      # geom = RGeo::GeoJSON.encode(place_geom.geometry)
      geom = place_geom.geometry

      if geom.class.to_s.downcase.include? 'collection'
        geom.each { |geo| @collection.push(geo) }
      else
        @collection.push(geom)
      end
    end

    def osm_geometries
      @osm_features = @converter.convert
      @osm_features[:features].each do |feature|
        next if feature[:properties][:type] == 'node'

        geom = RGeo::GeoJSON.decode(feature.to_json)
        @collection.push(geom.geometry)
      end
    end

    def lines_to_polygon
      lines = @collection.filter { |geom| geom.class.to_s.downcase.include? 'line' }.uniq
      return if lines.empty?

      points = @collection.filter { |geom| geom.class.to_s.downcase.include? 'point' }
      polygon = RGeo::Geos::CAPIGeometryCollectionImpl.create(@factory, lines).polygonize
      @collection = [*points]
      polygon.each { |poly| @collection.push poly } unless polygon.empty?
      lines.each { |line| @collection.push line } if polygon.empty?
    end

    def query
      body = @place.place_names.map do |p|
        "node[\"name\"=\"#{p.name}\"](around:500,#{@point[:lat]},#{@point[:lon]});way[\"name\"=\"#{p.name}\"](around:500,#{@point[:lat]},#{@point[:lon]});relation[\"name\"=\"#{p.name}\"](around:500,#{@point[:lat]},#{@point[:lon]});"
      end
      "[out:json][timeout:25];(#{body.join});out geom;"
    end
  end
end

# geo_factory = RGeo::Geographic.spherical_factory(srid: 4326)
# water = JSON.parse(File.read('SouthEastRiversStreams.geojson'), symbolize_names: true)
# names = water[:features].map { |w| w[:properties][:NAME] }.compact.uniq
# names.each do |name|
#   pn = CoreDataConnector::PlaceName.find_by(name:)
#   next if pn.nil?

#   place_geometry = pn.place.place_geometry
#   record_geom = place_geometry.geometry
#   geom_type = record_geom.class.to_s.downcase
#   record_point = if geom_type.include?('collection')
#                    record_geom.find { |g| g.class.to_s.downcase.include?('point')}
#                  elsif geom_type.include?('point')
#                    record_geom
#                  end
#   next if record_point.nil?

#   point = geo_factory.point(record_point.x, record_point.y)

#   line_strings = water[:features].filter { |f| f[:properties][:NAME] == name }
#   combined = Ecds::Helpers.combine_line_segments(line_strings)
#   place_geom = RGeo::GeoJSON.decode(combined.to_json, geo_factory:)
#   next if place_geom.nil?

#   geom = place_geom.geometry
#   points = if geom.class.to_s.downcase.include?('multi')
#              geom.map(&:points).flatten
#            else
#              geom.points
#            end
#   puts "no points for #{name}" if points.nil?

#   next if points.nil?

#   next unless points.any? { |line_point| point.distance(line_point) < 100 }

#   collection = RGeo::Geos::CAPIGeometryCollectionImpl.create(RGeo::Geos.factory(srid: 4326), [point, geom])
#   puts name
#   puts collection.class
#   place_geometry.update(geometry: collection)
# end
