# frozen_string_literal: true

require 'json'
require 'rgeo'
require 'rgeo/geo_json'
require 'httparty'

module Ecds
  #
  # Helpers for indexing place records.
  #
  module Helpers
    @factory = RGeo::Geographic.spherical_factory

    def self.thumbnail_url(provider, embed_id)
      case provider
      when 'Vimeo'
        "https://vumbnail.com/#{embed_id}.jpg"
      when 'YouTube'
        "https://img.youtube.com/vi/#{embed_id}/hqdefault.jpg"
      end
    end

    def self.embed_url(provider, embed_id)
      case provider
      when 'Vimeo'
        "https://player.vimeo.com/video/#{embed_id}"
      when 'YouTube'
        "https://www.youtube.com/embed/#{embed_id}"
      end
    end

    def self.feature_type(geometry)
      return :point if geometry.class.to_s.include? 'Point'
      return :polygon if geometry.class.to_s.include? 'Polygon'
      return :collection if geometry.class.to_s.include? 'Collection'

      nil
    end

    def self.feature_collection_template
      {
        type: 'FeatureCollection',
        features: []
      }
    end

    def self.feature_template(_record, properties, geometry)
      {
        type: 'Feature',
        properties:,
        geometry:
      }
    end

    def self.polygon_center_point(geometry)
      @factory.point(geometry.centroid.x, geometry.centroid.y)
    end

    def self.polygon_center(geometry)
      center = polygon_center_point(geometry)
      { lat: center.y, lon: center.x }
    end

    def self.line_center(geometry)
      # center = geometry.interpolate_point 0.5
      center = geometry.point_on_surface
      { lat: center.y, lon: center.x }
    end

    def self.collection_center_point(geometry)
      point = geometry.filter { |feature| feature.class.to_s.include? 'Point' }
      return @factory.point(point.first.x, point.first.y) unless point.empty?

      polygon = geometry.filter { |feature| feature.class.to_s.include? 'Polygon' }
      return polygon_center_point(polygon.first) unless polygon.empty?

      nil
    end


    def self.collection_center(geometry)
      point = geometry.filter { |feature| feature.class.to_s.include? 'Point' }
      polygon = geometry.filter { |feature| feature.class.to_s.include? 'Polygon' }
      line = geometry.filter { |feature| feature.class.to_s.include? 'Line' }
      return { lat: point.first.y, lon: point.first.x } unless point.empty?
      return polygon_center(polygon.first) unless polygon.empty?
      return line_center(line.first) unless line.empty?
      nil
    end

    def self.find_point(geometry)
      geom_type = feature_type(geometry)
      case geom_type
      when :point
        { lat: geometry.y, lon: geometry.x }
      when :polygon
        polygon_center(geometry)
      when :collection
        collection_center(geometry)
      end
    end

    def self.point(geometry)
      geom_type = feature_type(geometry)
      case geom_type
      when :point
        @factory.point(geometry.x, geometry.y)
      when :polygon
        polygon_center_point(geometry)
      when :collection
        collection_center_point(geometry)
      end
    end

    # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
    def self.geojson(record, properties)
      return if record.place_geometry.nil?

      geojson = feature_collection_template
      feature_geometry = RGeo::GeoJSON.encode(record.place_geometry.geometry)

      type = feature_type(record.place_geometry.geometry)

      case type
      when :collection
        feature_geometry['geometries'].each do |geometry|
          feature = feature_template(record, properties, geometry)
          geojson[:features].push(feature)
        end
      else
        geometry = feature_geometry
        feature = feature_template(record, properties, geometry)
        geojson[:features].push(feature)
      end

      geojson = geojson.deep_symbolize_keys

      geojson[:features].each do |f|
        f[:properties][:id] = "#{f[:geometry][:type].downcase}-#{f[:properties][:uuid]}"
        f[:id] = record.id
      end

      geojson
    end
    # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

    def self.check_for_geojson(record, document, model_mappings)
      geojson_field = model_mappings.select { |_key, value| value[:type] == 'geojson' }
      return nil if geojson_field.empty?

      property_fields = geojson_field.values.first[:property_fields].map(&:to_sym)
      properties = {}
      property_fields.each { |prop| properties[prop] = document[prop] }
      geojson(record, properties)
    end

    # Combine line segments by connecting endpoints, creating separate lines for gaps
    def self.connect_segments(segments)
      return [] if segments.empty?

      lines = []
      remaining = segments.dup

      until remaining.empty?
        current_line = remaining.shift.dup

        # Keep trying to extend the current line
        changed = true
        while changed && !remaining.empty?
          changed = false
          last_point = current_line.last

          # Find a segment that starts where we ended
          next_segment = remaining.find { |seg| seg.first == last_point }

          if next_segment
            # Remove the first point (duplicate) and append the rest
            current_line.concat(next_segment[1..])
            remaining.delete(next_segment)
            changed = true
          else
            # Check if any segment ends where we ended (reverse connection)
            next_segment = remaining.find { |seg| seg.last == last_point }

            if next_segment
              # Reverse the segment and append (excluding duplicate point)
              current_line.concat(next_segment.reverse[1..])
              remaining.delete(next_segment)
              changed = true
            end
          end
        end

        lines << current_line
      end

      lines
    end

    def self.combine_line_segments(features)
      # Extract all coordinate arrays from MultiLineString geometries
      all_coords = []
      features.each do |feature|
        next unless feature[:geometry][:type].include? 'Line'

        # Extract the first (and typically only) LineString from each MultiLineString
        feature[:geometry][:coordinates].each do |linestring|
          all_coords << linestring
        end
      end
      combined_lines = connect_segments(all_coords)
      if combined_lines.length == 1
        # Single continuous line
        {
          type: 'Feature',
          properties: features.first[:properties],
          geometry: {
            type: 'LineString',
            coordinates: combined_lines.first
          }
        }
      else
        # Multiple lines (gaps found)
        {
          type: 'Feature',
          properties: features.first[:properties],
          geometry: {
            type: 'MultiLineString',
            coordinates: combined_lines
          }
        }
      end
    end
  end
end
