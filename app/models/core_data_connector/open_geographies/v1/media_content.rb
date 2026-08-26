# frozen_string_literal: true

module CoreDataConnector
  module OpenGeographies
    module V1
      class MediaContent < ::CoreDataConnector::MediaContent
        include Searchable

        searchable_index 'open_geographies_v1'

        self.table_name = 'core_data_connector_media_contents'

        def extras
          {
            preview: resource_description&.content_preview_url,
            thumbnail: resource_description&.content_thumbnail_url,
            content_url: resource_description&.content_iiif_url,
            manifest_url:,
          }
        end
      end
    end
  end
end
