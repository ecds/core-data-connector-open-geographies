# frozen_string_literal: true

require 'elasticsearch'
require 'json'
# require_relative './document'

module Ecds
  # CRUD for Elasticsearch index
  class Indexer
    # rubocop:disable Metrics/MethodLength
    def initialize(collection:, collect_all: true, mapping: nil)
      @client = Elasticsearch::Client.new(
        host: ENV['ELASTICSEARCH_HOST'],
        api_key: ENV['ELASTICSEARCH_API_KEY'],
        retry_on_failure: true,
        transport_options: {
          request: { timeout: 20 }
        }
      )
      @collection = collection
      collections = File.read(File.join(Rails.root, 'app', 'lib', 'ecds', 'mappings.json'))
      mapping_key = mapping.nil? ? collection.to_sym : mapping.to_sym
      @collection_mappings = JSON.parse(collections, symbolize_names: true)[mapping_key]
      @collection_index = @collection_mappings.key?(:collection_index) ? @collection_mappings[:collection_index] : @collection
      @project_model_id = @collection_mappings[:project_model_id]
      project_model = CoreDataConnector::ProjectModel.find(@project_model_id)
      @model_class = project_model.model_class.constantize
      @documenter = Ecds::Document.new(project_model_id: @project_model_id, collection:)
      @enhancer_class = begin
        "Ecds::Enhance::#{collection.camelcase}".constantize
      rescue NameError
        nil
      end
      @records = @model_class.where(project_model_id: @project_model_id)
      document_count = @client.count(index: @collection_index)['count']
      documents = @client.search(
        index: @collection_index, body: {
          size: [document_count, @records.count].max,
          _source: false
        }
      )
      @hit_ids = documents['hits']['hits'].map { |h| h['_id'].to_s }
      @database_records = @records.map { |r| r.id.to_s } if collect_all
      @requests = []
      # index_requests unless collect_all
    end
    # rubocop:enable Metrics/MethodLength

    def create
      document_mappings = @collection_mappings[:mappings]
      @client.indices.create(index: @collection_index, body: { mappings: document_mappings })
    end

    def delete
      @client.indices.delete(index: @collection_index)
    end

    def index
      index_requests
    end

    def update
      puts "#{Time.now.to_datetime} UPDATING #{@collection}"
      index_requests

      return if @project_model_id == 25
      return if @collection.include?('counties')

      @database_records.concat CoreDataConnector::Place.where(project_model_id: 25).map(&:id).map(&:to_s)

      @hit_ids.reject! { |hit| @database_records.include? hit }

      @hit_ids.each do |hit|
        @requests.push({ delete: { _index: @collection_index, _id: hit } })
      end

      post unless @requests.empty?
    end

    def index_record(record_id)
      record = @model_class.find(record_id)
      document = @documenter.to_document(record)
      document = enhance(document) unless @enhancer_class.nil?
      begin
        @client.get(index: @collection_index, id: record.id)
        @client.update(index: @collection_index, id: record.id, body: { doc: document })
      rescue Elasticsearch::Transport::Transport::Errors::NotFound
        @client.index(index: @collection_index, body: document)
      end
    end

    def delete_record(record_id)
      @client.delete(index: @collection_index, id: record_id)
    end

    def post
      @client.bulk(body: @requests.compact)
      @requests = []
    end

    private

    def index_requests
      # total = @records.count
      count = 1
      @records.in_groups_of(50) do |group|
        next if group.nil?

        @requests = []
        group.each do |record|
          next if record.nil?

          # puts "#{count} of #{total} - #{record.name}"
          document = @documenter.to_document(record)
          begin
            document = enhance(document) unless @enhancer_class.nil?
            if @hit_ids.include?(record.uuid)
              @requests.push({ update: { _index: @collection_index, _id: record.id, data: { doc: document } } })
            else
              @requests.push({ index: { _index: @collection_index, _id: record.id, data: document } })
            end
            count += 1
          rescue StandardError => e
            puts "#{Time.now.to_datetime} ERROR #{@collection}: #{record.name}"
            puts "#{Time.now.to_datetime} ERROR #{e}"
          end
        end
        # puts '************* posting ************'
        post
      end
    end

    def enhance(document)
      enhancer = @enhancer_class.new document
      enhancer.enhance
    end
  end
end

# ActiveRecord::Base.logger = nil
# record = CoreDataConnector::Place.find(3430)
# documenter = Ecds::Document.new(project_model_id: 6, collection: 'georgia_coast_places')
# document = documenter.to_document record
# enhancer = Ecds::Enhance::GeorgiaCoastPlaces.new document
# document = enhancer.enhance
