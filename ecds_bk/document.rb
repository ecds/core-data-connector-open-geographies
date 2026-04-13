# frozen_string_literal: true

require 'json'
    # require_relative './helpers'

    module Ecds
      # Class to generate document for indexing
      class Document
        attr_reader :client, :collection

        def initialize(project_model_id:, collection: nil, mappings: nil)
          @project_model_id = project_model_id
          if collection
            @collection = collection
            mappings_file = File.read(File.join(Rails.root, 'app', 'lib', 'ecds', 'mappings.json'))
            @model_mappings = JSON.parse(mappings_file, symbolize_names: true)[collection.to_sym][:model_fields]
          end
          @model_mappings = mappings if mappings
        end

        # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength
        def to_document(record)
          document = { model_id: @project_model_id, suppress: 'no' }
          @model_mappings.each_key do |model_field|
            field = @model_mappings[model_field]
            case field[:type]
            when 'string'
              document[model_field] = record.send(field[:field])
            when 'names'
              document[:names] = CoreDataConnector::PlaceName.where(place_id: record.id).map(&:name)
            when 'user_defined'
              document[model_field] = if field[:sub_field] && record.user_defined[field[:field]]
                                        record.user_defined[field[:field]][field[:sub_field]]
                                      else
                                        record.user_defined[field[:field]]
                                      end
            when 'related'
              relations = if field[:primary]
                            CoreDataConnector::Relationship.where(
                                          primary_record_id: record.id,
                                          project_model_relationship_id: field[:related_model_id]
                                        )
                          else
                            CoreDataConnector::Relationship.where(
                                          related_record_id: record.id,
                                          project_model_relationship_id: field[:related_model_id]
                                        )
                          end
              if field[:related_type] == 'string' || field[:related_type] == 'array'
                related_records = relations.map do |related_record|
                  # Converts string to callable class name.
                  if field[:primary]
                    klass = related_record.related_record_type.constantize
                    klass.find(related_record.related_record.id).send(field[:field])
                  else
                    klass = related_record.primary_record_type.constantize
                    klass.find(related_record.primary_record.id).send(field[:field])
                  end
                end
                related_records = field[:related_type] == 'string' ? related_records.first : related_records.uniq.compact
                document[model_field] = related_records
              end
              if field[:related_type] == 'hash'
                document[model_field] = relations.map do |related_record|
                  props = {}
                  if field[:related_fields]
                    field[:related_fields].each do |related_field|
                      user_defined_field = UserDefinedFields::UserDefinedField.find_by(uuid: related_field)
                      props[user_defined_field.column_name.parameterize.underscore] = related_record.user_defined[related_field]
                    end
                  end
                  related_klass = if field[:primary]
                                    related_record.related_record_type.constantize
                                  else
                                    related_record.primary_record_type.constantize
                                  end
                  related_instance = if field[:primary]
                                       related_klass.find(related_record.related_record.id)
                                     else
                                       related_klass.find(related_record.primary_record.id)
                                     end
                  field[:field].each do |prop|
                    if related_instance.respond_to?(prop)
                      props[prop] = related_instance.send(prop)
                    else
                      user_defined_field = UserDefinedFields::UserDefinedField.find_by(uuid: prop)
                      props[user_defined_field.column_name.parameterize.underscore] = related_instance.user_defined[prop]
                    end
                  end
                  props
                end
              end
              # if field[:related_type] == 'place_layer'
              #   props = {}
              #   related_records = relations.map do |related_record|
              #     # Converts string to callable class name.
              #     klass = related_record.related_record_type.constantize
              #     klass.find(related_record.related_record.id).send(field[:field])
              #   end
              # end
            when 'geo_point'
              document[model_field] = Ecds::Helpers.find_point(record.place_geometry.geometry) unless record.place_geometry.nil?
            when 'slug'
              document[:slug] = record.send(field[:field]).parameterize
            when 'manifests'
              document[:manifests] = record.manifests.map do |m|
                {
                  label: m.label.parameterize.underscore,
                  identifier: "#{ENV['HOSTNAME']}#{m.identifier}"
                }
              end
            when 'bbox'
              if record.place_geometry
                bbox = RGeo::Cartesian::BoundingBox.create_from_geometry record.place_geometry.geometry
                document[:bbox] = [bbox.min_x, bbox.min_y, bbox.max_x, bbox.max_y]
              end
            else
              next
            end
          end
          geojson = Ecds::Helpers.check_for_geojson(record, document, @model_mappings)
          document[:geojson] = geojson unless geojson.nil?
          document.deep_symbolize_keys!
        end
        # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength

        private

        def nested_fields(record, fields)
          copy = record
          fields.each do |field|
            copy = copy.send(field)
          end
          copy
        end
      end
    end
