require "searchkick"

module ::CoreDataConnector
  module OpenGeographies
    module Searchable
      extend ActiveSupport::Concern

      included do
        searchkick deep_paging: true,
                   callbacks: false,
                   index_name: -> { "#{name.pluralize.parameterize(separator: "_")}" }
      end

        def search_data
          {
            **base_search_data,
            **user_defined_fields,
            **extras,
            **related,
            **related_to
          }
        end

        def base_search_data
          {
            id:,
            uuid:,
            name:,
            slug:,
            slugs:,
            project: project.name.parameterize,
            class_name: self.class.name
          }
        end

        def related_search_data
          {
            **base_search_data,
            **extras,
            **related
          }
        end

        private

        def part_of_rel_model
          ::CoreDataConnector::ProjectModelRelationship.where(
            related_model: project_model,
            inverse_name: "Part of"
          )
        end

        def parent
          ::CoreDataConnector::Relationship.find_by(
            project_model_relationship: part_of_rel_model,
            related_record: self
          ).primary_record
        end

        def slug
          name.parameterize
        end

        def slugs
          case self.class.name
          when "CoreDataConnector::OpenGeographies::Place"
            place_names.map { |place_name| place_name.name.parameterize }
          else
            [ name.parameterize ]
          end
        end

        def user_defined_fields(record = self)
          return {} if record.user_defined.nil?

          fields = case record.class.name
          when "::CoreDataConnector::Relationship"
            record.project_model_relationship.user_defined_fields
          else
            record.project_model.user_defined_fields
          end

          attributes = {}
          record.user_defined.each do |key, value|
            user_defined_field = fields.find_by(uuid: key)
            next if user_defined_field.nil?

            label = user_defined_field.column_name
            attributes[label.parameterize.underscore.to_sym] = { label:, value: }
          end

          attributes
        end

        def related
          related_records = {}

          relations = ::CoreDataConnector::ProjectModelRelationship.where(primary_model: project_model)

          relations.each_with_index do |rel, idx|
            next if rel.name == "County"

            if rel.multiple
              records = ::CoreDataConnector::Relationship.where(project_model_relationship: rel, primary_record: self)
              next if records.empty?
              related_records[rel.name.parameterize.underscore.to_sym] = records.map do |relation|
                related_class(relation.related_record_type).find(
                  relation.related_record.id
                ).related_search_data
              end
            else
              relation = ::CoreDataConnector::Relationship.find_by(project_model_relationship: rel, primary_record: self)
              next if relation.nil?
              related_records[rel.name.parameterize.underscore.to_sym] = related_class(
                relation.related_record_type
              ).find(relation.related_record_id).related_search_data
            end
          end

          related_records
        end

        def related_to
          related_records = {}

          return related_records if @related

          relations = ::CoreDataConnector::ProjectModelRelationship.where(related_model: project_model)

          relations.each do |rel|
            next unless rel.allow_inverse

            if rel.multiple
              records = ::CoreDataConnector::Relationship.where(project_model_relationship: rel, related_record: self).map(&:primary_record)
              next if records.empty?

              related_records[rel.inverse_name.parameterize.underscore.to_sym] = records.map do |relation|
                related_class(relation.primary_record_type).find(
                  relation.primary_record.id
                ).base_search_data
              end

            else
              relation = ::CoreDataConnector::Relationship.find_by(project_model_relationship: rel, related_record: self)
              next if relation.nil?
              related_records[rel.inverse_name.parameterize.underscore.to_sym] = related_class(
                relation.primary_record_type
              ).find(relation.primary_record_id).base_search_data
            end
          end

          related_records
        end

        def extras
          {}
        end

        def related_class(related_record_type)
          "::CoreDataConnector::OpenGeographies::#{related_record_type.split("::").last}".constantize
        end
    end
  end
end
