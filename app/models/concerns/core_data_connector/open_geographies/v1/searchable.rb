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
      # model_name rather than by which index a document lives in.
      #
      # Relationship/UDF *promotion* (types, media, contained_in_place, ...)
      # works entirely by exact name match against PromotedRelationships,
      # which is derived from og_schema/canonical_template.json rather than a
      # database flag - see that module for why (short version: a flag would
      # need new columns on ProjectModelRelationship/UserDefinedField in
      # core-data-connector, a repo this engine doesn't own and can't diverge
      # from indefinitely). Everything - promoted or not - still gets indexed
      # under its own raw name-derived key too, same as v0 does today, so a
      # bespoke per-atlas client isn't limited to only the promoted subset.
      module Searchable
        extend ActiveSupport::Concern

        MAPPING_PATH = ::CoreDataConnector::OpenGeographies::Engine.root.join(
          'lib', 'core_data_connector_open_geographies', 'v1', 'es_mapping.json'
        )
        MAPPING = JSON.parse(File.read(MAPPING_PATH), symbolize_names: true).freeze

        # How many levels deep a related record's own relationships get
        # expanded when nested inside this record's document (a Place's
        # media[] entries include their own creator/publisher, but *those*
        # don't get their relationships expanded again). v0's equivalent
        # (related_search_data) has no such limit - it recurses for as long
        # as the relationship graph keeps producing new records, which only
        # terminates today because nothing in the current schema happens to
        # cycle back. That's fragile by accident, not by design; this makes
        # the limit explicit instead of trusting the graph shape to stay
        # accidentally acyclic.
        DEFAULT_DEPTH = 1

        # Explicit per-class call rather than a fixed `included do`: v0-style
        # "everything shares one index" was true when this concern only had
        # one caller, but Map Layers needs its own index (bbox geo_shape
        # queries, a different document shape) - see V1::MapLayer. Every
        # including class must call this once; there's no silent default,
        # so it's always visible in the model file which index a class
        # writes to.
        class_methods do
          def searchable_index(name, mapping: Searchable::MAPPING)
            searchkick(
              index_name: -> { name },
              callbacks: false,
              deep_paging: true,
              mappings: mapping[:mappings],
              settings: mapping[:settings],
            )
          end
        end

        # CoreDataConnector::WebIdentifier stores a bare code (VIAF "143125668",
        # not "https://viaf.org/viaf/143125668/"), so `sameAs` needs the URL built
        # per authority - CoreDataConnector::Authority::* (WebIdentifier's own
        # reconciliation services) don't help here, they call each authority's API
        # for lookup/search, not its public entity page. Only the authorities
        # verified against a real canonical URL pattern are listed; anything else
        # in WebAuthority::SOURCE_TYPES (atom, bnf, dpla, jisc) falls back to the
        # raw stored value rather than risk emitting a fabricated wrong URL.
        IDENTIFIER_URL_BUILDERS = {
          'wikidata' => ->(id) { "https://www.wikidata.org/wiki/#{id}" },
          'geonames' => ->(id) { "https://www.geonames.org/#{id}" },
          'viaf' => ->(id) { "https://viaf.org/viaf/#{id}/" },
        }.freeze

        # Not marked `private`: cross-instance calls (related/summarize invoking
        # these on *other* records' instances) need them callable with an
        # explicit receiver, matching v0's Searchable for the same reason.
        #
        # base_search_data + extras are seeded first and never suffixed - both
        # are developer-controlled (this file, or a model's own #extras
        # override), not curator-entered, so they're structurally guaranteed
        # not to collide with each other. Everything after that is
        # curator-controlled (relationship names, UDF column names) and goes
        # through assign_unique! against the accumulating hash, since Core
        # Data enforces no uniqueness on those names at all - see
        # assign_unique! for why that matters.
        def search_data
          data = { **base_search_data, **extras }

          [user_defined_fields, related(DEFAULT_DEPTH), related_to(DEFAULT_DEPTH), featured].each do |additions|
            additions.each { |key, value| assign_unique!(data, key, value) }
          end

          data
        end

        def base_search_data
          {
            uuid:,
            slug:,
            slugs:,
            project_id: project_model.project_id.to_s,
            # The parameterized project name, matching what v1's routes
            # actually key on (GET /v1/:project/places/:slug resolves
            # :project via Project#name.parameterize - there's no dedicated
            # slug column on Project). project_id alone can't build a URL:
            # it's fine for a record's own top-level document (the client
            # already knows what project it asked for), but a *nested*
            # summary - Contained In pointing at a record in a different,
            # shared project (see the Administrative Districts project) -
            # would otherwise carry a project_id with no way to turn it into
            # a fetchable link at all.
            project: project_model.project.name.parameterize,
            model_type: PromotedRelationships.model_type_for(self),
            model_id: project_model.id.to_s,
            model_name: project_model.name,
            name:,
            visibility: 'published', # no draft/suppress concept in CoreDataConnector today - placeholder until one exists
            date_modified: updated_at&.iso8601,
            identifiers:,
          }
        end

        # {authority, identifier} per schema.org sameAs - derived from Identifiable's
        # web_identifiers association, which several but not all OG-eligible models
        # include, hence the respond_to? guard rather than assuming universality.
        def identifiers
          return [] unless respond_to?(:web_identifiers)

          web_identifiers.map do |web_identifier|
            authority = web_identifier.web_authority.source_type
            builder = IDENTIFIER_URL_BUILDERS[authority]
            {
              authority:,
              identifier: builder ? builder.call(web_identifier.identifier) : web_identifier.identifier,
            }
          end
        end

        # Every scalar UDF this record has a value for, keyed by its
        # column_name (parameterized/underscored) as `{label:, value:}` -
        # that part is ported unchanged from v0, and stays regardless of
        # promotion status, same "index it under its own name too" rule
        # `related` uses.
        #
        # Additionally, per PromotedRelationships.udfs_for: a UDF whose
        # column_name exact-matches a canonical name gets ALSO written under
        # its promoted path, as a bare value (no {label:,value:} wrapper) -
        # a single-segment path like "date" writes a flat key; a dotted path
        # like "source.type"/"source.urls" merges into one `source: {type:,
        # urls:}` object. When a UDF's raw key and promoted path happen to
        # be the same string (e.g. Map Layers' "Description" -> "description"),
        # the promoted (bare-value) write simply overwrites the raw
        # (label/value) write at that key - matching how `related` already
        # collapses raw and promoted keys when a curator used the exact
        # canonical relationship name.
        def user_defined_fields(record = self)
          return {} if record.user_defined.nil?

          fields = record.project_model.user_defined_fields
          promoted = PromotedRelationships.udfs_for(record)

          attributes = {}
          record.user_defined.each do |key, value|
            user_defined_field = fields.find_by(uuid: key)
            next if user_defined_field.nil?

            label = user_defined_field.column_name
            assign_unique!(attributes, label.parameterize.underscore.to_sym, { label:, value: })

            # Not collision-guarded: promoted paths are developer-controlled
            # (they come from our own canonical template, not curator input),
            # and a dotted path is *meant* to write into the same top-level
            # key as a sibling UDF's dotted path (source.type + source.urls
            # both target :source) - that's the intended merge, not a clash.
            promoted_path = promoted[label]
            merge_promoted_udf!(attributes, promoted_path, value) if promoted_path
          end

          attributes
        end

        # Per-model override point for fields that don't need the promote
        # mechanism to be safely hand-written today (e.g. Place's geometry).
        def extras
          {}
        end

        # Walks every relationship *from* this record. Everything is indexed
        # under its own name-derived key regardless of promotion status;
        # promoted relationships (exact name match against
        # PromotedRelationships.for(self)) *additionally* get written under
        # their well-known canonical key, in one of two shapes: a bare array
        # of names for relationships pointing at a Taxonomy (types, work_type
        # - these exist purely for faceted filtering, not navigation, so a
        # plain string is enough), or a depth-limited summary object for
        # everything else (contained_in_place, media, creator, ... - these
        # need uuid/slug so a client can link to the record itself).
        def related(depth = DEFAULT_DEPTH)
          related_records = {}
          promoted = PromotedRelationships.for(self)

          relations = ::CoreDataConnector::ProjectModelRelationship.where(primary_model: project_model)

          relations.each do |rel|
            promoted_key = promoted[rel.name]
            raw_key = rel.name.parameterize.underscore.to_sym

            if rel.multiple
              records = ::CoreDataConnector::Relationship.where(project_model_relationship: rel, primary_record: self)
              next if records.empty?

              items = records.map { |relation| related_class(relation.related_record_type).find(relation.related_record_id) }
              written_key = assign_unique!(related_records, raw_key, items.map { |item| summarize(item, depth) })
              assign_promoted!(related_records, promoted_key, raw_key, written_key, promoted_value(items, rel, depth)) if promoted_key
            else
              relation = ::CoreDataConnector::Relationship.find_by(project_model_relationship: rel, primary_record: self)
              next if relation.nil?

              item = related_class(relation.related_record_type).find(relation.related_record_id)
              written_key = assign_unique!(related_records, raw_key, summarize(item, depth))
              assign_promoted!(related_records, promoted_key, raw_key, written_key, promoted_value(item, rel, depth)) if promoted_key
            end
          end

          related_records
        end

        # The inverse direction - relationships where this record is the
        # *target* - surfaced only when the relationship explicitly allows it
        # (allow_inverse). No promotion pass here: the canonical template
        # only defines promoted names for the forward direction today (e.g.
        # "Contained In" -> contained_in_place, but no promoted name for its
        # "Contains" inverse). If that changes, this needs the same
        # promoted-lookup treatment `related` has.
        #
        # Branches on rel.inverse_multiple, not rel.multiple - the forward
        # and inverse directions have independent cardinality (Core Data
        # gives them separate columns for exactly this: a County has_many
        # Places is multiple=true, but each Place belongs to exactly one
        # County, inverse_multiple=false). v0's equivalent branches on
        # rel.multiple for both directions, which is wrong whenever the two
        # differ - not carried forward here.
        def related_to(depth = DEFAULT_DEPTH)
          related_records = {}

          relations = ::CoreDataConnector::ProjectModelRelationship.where(related_model: project_model)

          relations.each do |rel|
            next unless rel.allow_inverse

            key = rel.inverse_name.parameterize.underscore.to_sym

            if rel.inverse_multiple
              records = ::CoreDataConnector::Relationship.where(project_model_relationship: rel, related_record: self)
              next if records.empty?

              value = records.map do |relation|
                summarize(related_class(relation.primary_record_type).find(relation.primary_record_id), depth)
              end
            else
              relation = ::CoreDataConnector::Relationship.find_by(project_model_relationship: rel, related_record: self)
              next if relation.nil?

              value = summarize(related_class(relation.primary_record_type).find(relation.primary_record_id), depth)
            end

            assign_unique!(related_records, key, value)
          end

          related_records
        end

        # Ported from v0 largely as-is: a relationship carrying a Boolean UDF
        # whose column_name contains "featured" promotes whichever related
        # record has that box checked to a singular `{relationship_name}:`
        # key - e.g. Place's featured_media. Distinct from the name-based
        # relationship promotion above: this is curator-defined (any
        # relationship can carry a Featured UDF), not tied to the fixed
        # canonical name list, so there's no compliance concept here, just
        # "index it if it's there."
        def featured
          featured_recs = {}

          relations = ::CoreDataConnector::ProjectModelRelationship.where(primary_model: project_model)

          featureable_fields = relations.flat_map do |rel|
            rel.user_defined_fields.select { |ud| ud.column_name.downcase.include?('featured') && ud.data_type == 'Boolean' }
          end.compact

          featureable_fields.each do |featured_field|
            project_model_relationship = ::CoreDataConnector::ProjectModelRelationship.find(featured_field.defineable_id)
            rels = ::CoreDataConnector::Relationship.where(project_model_relationship:, primary_record: self)
            featured_rel = rels.find { |rel| rel.user_defined[featured_field.uuid] }
            next if featured_rel.nil?

            item = related_class(featured_rel.related_record_type).find(featured_rel.related_record_id)
            key = project_model_relationship.name.parameterize.underscore.singularize.to_sym
            assign_unique!(featured_recs, key, summarize(item, 0))
          end

          featured_recs
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

        private

        # Depth-limited summary of a related record: at depth 0, just the flat
        # envelope plus its own extras, no further relationship expansion
        # (this is what actually stops the recursion, unlike v0's equivalent).
        # Above 0, one more layer of that record's own relationships.
        def summarize(record, depth)
          base = { **record.base_search_data, **record.extras }
          return base if depth <= 0

          { **base, **record.related(depth - 1), **record.related_to(depth - 1) }
        end

        # Bare name(s) for a promoted relationship pointing at a Taxonomy
        # (facet-only, no navigation needed); a depth-limited summary
        # otherwise (needs uuid/slug so a client can link to it).
        def promoted_value(items_or_item, rel, depth)
          if taxonomy_relationship?(rel)
            if items_or_item.is_a?(Array)
              items_or_item.map(&:name)
            else
              items_or_item.name
            end
          elsif items_or_item.is_a?(Array)
            items_or_item.map { |item| summarize(item, depth) }
          else
            summarize(items_or_item, depth)
          end
        end

        def taxonomy_relationship?(rel)
          rel.related_model.model_class == 'CoreDataConnector::Taxonomy'
        end

        # Writes `value` at `key`, appending an incrementing numeric suffix
        # (_2, _3, ...) if `key` is already taken. Core Data enforces no
        # uniqueness on ProjectModelRelationship#name or UserDefinedField
        # #column_name - only `presence` is validated (checked against the
        # gem source directly) - so two different relationships, or two
        # different UDFs, or a relationship and a UDF, genuinely can
        # parameterize to the identical key. A plain hash-key overwrite would
        # drop one value with no trace; suffixing keeps both and makes the
        # collision visible in the response instead of silently losing data.
        # Returns the key actually used, since callers sometimes need to
        # know whether their own write landed cleanly.
        def assign_unique!(hash, key, value)
          candidate = key
          n = 2
          while hash.key?(candidate)
            candidate = :"#{key}_#{n}"
            n += 1
          end
          hash[candidate] = value
          candidate
        end

        # Promoted-key write for `related`. When `promoted_key` is literally
        # the same string as this relationship's own raw key *and* that raw
        # write actually landed there unsuffixed (`written_key == raw_key`),
        # the promoted (cleaner) shape intentionally replaces it - a curator
        # used the exact canonical name, so raw and promoted are the same
        # relationship, not a collision. If the raw write got bumped to
        # `_2` because an *earlier* relationship already held that key, this
        # relationship's promoted value must not fall back to overwriting
        # that earlier relationship's slot - it goes through assign_unique!
        # like any other value instead.
        def assign_promoted!(hash, promoted_key, raw_key, written_key, value)
          if promoted_key == raw_key && written_key == raw_key
            hash[promoted_key] = value
          else
            assign_unique!(hash, promoted_key, value)
          end
        end

        # Writes `value` into `attributes` at a dotted path, creating
        # intermediate hashes as needed ("source.type" + "source.urls" both
        # writing into the same `attributes[:source]` hash).
        def merge_promoted_udf!(attributes, path, value)
          segments = path.split('.').map(&:to_sym)
          target = segments[0..-2].reduce(attributes) { |hash, segment| hash[segment] ||= {} }
          target[segments.last] = value
        end

        def related_class(related_record_type)
          "::CoreDataConnector::OpenGeographies::V1::#{related_record_type.split("::").last}".constantize
        end
      end
    end
  end
end
