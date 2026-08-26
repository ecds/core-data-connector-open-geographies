# frozen_string_literal: true

require 'uri'
require 'cgi'
require 'httparty'
require 'aws-sdk-s3'

module Ecds
  #
  # Transform IIIF Cloud links to ECDS IIP links.
  # Migrate files to IIP if needed.
  #
  class Image
    def initialize(download_url:)
      begin
        response = HTTParty.get(download_url, follow_redirects: false)
        uri = URI(response.headers[:location])
      rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ETIMEDOUT
        sleep(5)
        retry
      end
      @key = uri.path.include?('iiif') ? uri.path.split('/')[3] : uri.path.split('/').last
      @destination_key = "images/#{@key}"
      @source_bucket = Aws::S3::Bucket.new('ecds-cantaloupe')
      @destination_bucket = Aws::S3::Bucket.new('ecds-iiif')
      @trigger_bucket = Aws::S3::Bucket.new('readux-s3-ingest')
      @source_object = @source_bucket.object(@key)
      @destination_object = Aws::S3::Object.new(@destination_bucket.name, @destination_key)
    end

    def versions
      {
        thumbnail_url: "#{base_url}/square/!250,250/0/default.jpg",
        full_url: "#{base_url}/full/max/0/default.jpg",
        info: "#{base_url}/info.json",
      }
    end

    def migrated?
      @destination_object.exists? && @destination_object.last_modified > @source_object.last_modified
    end

    def migrate
      return if migrated?

      @source_object.copy_to(bucket: @destination_bucket.name, key: "incoming/#{@key}")
      upload_trigger_file(filename: "#{DateTime.now.to_i}.txt", bucket: @trigger_bucket)
    end

    private

    def base_url
      "https://iiif.ecds.io/iiif/3/#{@key}"
    end

    def upload_trigger_file(filename:, bucket:)
      File.open(filename, 'w') do |file|
        file.puts @key
      end
      trigger_file = Aws::S3::Object.new(bucket.name, filename)
      trigger_file.upload_file(filename)
    end
  end
end
