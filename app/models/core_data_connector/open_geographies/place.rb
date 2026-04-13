module CoreDataConnector
  module OpenGeographies
    class Place < ::CoreDataConnector::Place
      include Searchable

      self.table_name = "core_data_connector_places"

      private

      # def slug
      #   place_names = CoreDataConnector::PlaceName.where(name: name).filter { |pn| pn.place.project_model == project_model }
      #   return name.parameterize if place_names.count == 1

      #   parent_rels_count = place_names.map do |pn|
      #     CoreDataConnector::Relationship.where(
      #       project_model_relationship: part_of_rel_model,
      #       primary_record: parent,
      #       related_record: pn.place
      #     ).count
      #   end

      #   return "#{name} #{parent.name} #{id}".parameterize if parent_rels_count > 1

      #   "#{name} #{parent.name}".parameterize
      # end

      def extras
        {
          geometry: place_geometry.to_geojson,
          names: place_names.map(&:name),
          place_layers: place_layers.map do |pl|
            {
              id: pl.id,
              name: pl.name,
              slug: pl.name.parameterize,
              type: pl.layer_type,
              url: pl.url,
              content: pl.content.nil? ? {} : JSON.parse(pl.content, symbolize_names: true)
            }
          end
        }
      end
    end
  end
end
