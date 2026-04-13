module OpenGeographies
  class Osm < ::CoreDataConnector::Authority::Base
    include CoreDataConnector::Http::Requestable

    BASE_URL = "https://nominatim.openstreetmap.org"
    HEADERS = { 'Referer': ENV["HOSTNAME"] }

    def find(id)
      options = {
        method: :get,
        headers: HEADERS,
        params: {
          osm_ids: id,
          format: "json",
          polygon_geojson: 1
        }
      }
      send_request("#{BASE_URL}/lookup.php", options) do |response|
        JSON.parse(response, symbolize_names: true)
      end
    end

    def search(query, _ = {})
      params = {
        q: query.gsub(" ", "+"),
        format: "json"
      }
      send_request("#{BASE_URL}/search", method: :get, params:, headers: HEADERS) do |body|
        JSON.parse(body)
      end
    end

    def geojson_feature(geometries)
      coordinates = geometries.map { |geom| [ geom[:lon], geom[:lat] ] }
      type = coordinates.first == coordinates.last ? "Polygon" : "LineString"
      coordinates = type == "Polygon" ? [ coordinates ] : coordinates
      {
        type: "Feature",
        properties: {},
        geometry: {
          coordinates:,
          type:
        }
      }
    end

    def geojson_features(geometries)
      return geojson_feature(geometries) if geometries.first.instance_of?(Hash)

      geometries.map do |geometry|
        geojson_feature(geometry)
      end
    end

    def way(osm_data)
      geometries = osm_data[:elements].map { |e| e }
      return if geometries.empty?

      geojson_features(geometries)
    end

    def relation(osm_data)
      relations = osm_data[:elements].filter { |e| e[:type] == "relation" }
      return if relations.empty?

      features = []
      ways = relations.map { |r| r[:members].filter { |member| member[:type] == "way" } }.flatten
      ways.map { |m| m[:geometry] }.map { |g| g }.each do |geometries|
        features.push(geojson_features(geometries))
      end

      features
    end

    def geojson(id, type: "way")
      puts type
      osm_data = find(id, type:)
      features = type == "way" ? way(osm_data) : relation(osm_data)
      {
        type: "FeatureCollection",
        features:
      }.to_json
    end
  end
end
# CoreDataConnector::WebIdentifier.where(web_authority_id: 1).each do |wd|
#   record = CoreDataConnector::Place.find(wd.identifiable_id)
#   next unless record.project_model_id == 6
#   data = wd_auth.find(wd.identifier).deep_symbolize_keys
#   if data[:entities][wd.identifier.to_sym]
#     if data[:entities][wd.identifier.to_sym][:claims][:P402]
#       osm = data[:entities][wd.identifier.to_sym][:claims][:P402].map {|m|m[:mainsnak]}.map {|d| d[:datavalue][:value]}
#       puts osm
#       record.user_defined['48210d8d-9a9b-4dcb-855e-8bb8ae6ce979'] = osm
#       record.save
#     end
#   end
# end; nil
