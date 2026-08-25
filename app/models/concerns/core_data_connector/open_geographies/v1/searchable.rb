# frozen_string_literal: true

require 'searchkick'

module CoreDataConnector
  module OpenGeographies
    module V1
      # v1's indexing concern, structurally distinct from (not a subclass/reuse
      # of) CoreDataConnector::OpenGeographies::Searchable: v0 gives every model
      # class its own index, named after the class; v1 gives every model class
      # the *same* index_name ('open_geographies_v1'), so Searchkick writes them
      # all into one shared physical index - the "one mapping serves every
      # atlas" design in og_schema/README.md - discriminated by model_type /
      # model_name rather than by which index a document lives in. Querying
      # across that shared index goes through Searchkick.search(index_name:) /
      # any one participating class's .search with load: false, not per-class
      # .search assuming an isolated index.
      #
      # search_data here only covers what's honestly derivable from today's
      # schema (structural envelope fields + whatever a model's own `extras`
      # adds, e.g. geometry). Relationship/UDF promotion (types, media,
      # contained_in_place, description, ...) needs the og.promote/og.intent
      # metadata proposed in og_schema/canonical_template.json to actually exist
      # on ProjectModelRelationship and UserDefinedField in core-data-connector -
      # that's a separate decision for that repo, not implemented here yet.
      module Searchable
        extend ActiveSupport::Concern

        MAPPING_PATH = ::CoreDataConnector::OpenGeographies::Engine.root.join(
          'lib', 'core_data_connector_open_geographies', 'v1', 'es_mapping.json'
        )
        MAPPING = JSON.parse(File.read(MAPPING_PATH), symbolize_names: true).freeze

        included do
          searchkick index_name: -> { 'open_geographies_v1' },
            callbacks: false,
            deep_paging: true,
            mappings: MAPPING[:mappings],
            settings: MAPPING[:settings]
        end

        # Not marked `private`, matching v0's Searchable: related_search_data-style
        # cross-instance calls (once relationship promotion exists here) need to
        # invoke these on *other* records' instances, which requires them to stay
        # callable with an explicit receiver.
        def search_data
          {
            **base_search_data,
            **extras,
          }
        end

        def base_search_data
          {
            uuid:,
            slug:,
            slugs:,
            project_id: project_model.project_id.to_s,
            model_type: self.class.name.demodulize.underscore,
            model_name: project_model.name,
            name:,
            visibility: 'published', # no draft/suppress concept in CoreDataConnector today - placeholder until one exists
            date_modified: updated_at&.iso8601,
          }
        end

        # Per-model override point for fields that don't need the promote
        # mechanism to be safely hand-written today (e.g. Place's geometry).
        def extras
          {}
        end

        def slug
          ud_slug = project_model.user_defined_fields.find { |ud| ud.column_name.downcase.include?('slug') }
          ud_slug.nil? ? name.parameterize : user_defined[ud_slug.uuid]
        end

        def slugs
          ud_slugs = project_model.user_defined_fields
            .filter { |ud| ud.column_name.downcase.include?('slug') }
            .map { |ud| user_defined[ud.uuid] }

          [*ud_slugs, name.parameterize].compact.uniq
        end
      end
    end
  end
end
