# frozen_string_literal: true

# lib/tasks/ecds_pmtiles.rake

require 'fileutils'
require 'optparse'
require 'aws-sdk-s3'
require 'aws-sdk-cloudfront'

namespace :core_data_connector do
  namespace :open_geographies do
    namespace :index do
    end

    namespace :pmtiles do
      desc 'Create PMTiles with a number and array of numbers'
      task create: :environment do
        options = {}

        opt_parser = OptionParser.new do |opts|
          opts.banner = 'Usage: rake ecds_pmtiles:create -- [options]'

          opts.on('-T', '--type STRING', String, 'Name of specific type.') do |type|
            options[:type] = type.sub('=', '')
          end

          opts.on('-t', '--taxonomy NUMBER', Integer, 'Single Project Model ID for Taxonomy Model.') do |t|
            options[:taxonomy_model] = t
          end

          opts.on('-s', '--skip-upload', 'Skip uploading new file.') do |_s|
            options[:skip] = true
          end

          opts.on('-h', '--help', 'Show this help message') do
            exit
          end
        end

        args = opt_parser.order!(ARGV.drop(1))
        opt_parser.parse!(args)

        tmp_dir = File.join(Rails.root, 'tmp', 'pmtiles')

        FileUtils.mkdir_p(tmp_dir)
        builder = Tippecanoe::Builder.new
        project_model = CoreDataConnector::ProjectModel.find(options[:taxonomy_model])
        types = if options[:type].nil?
          CoreDataConnector::Taxonomy.where(project_model:)
        else
          CoreDataConnector::Taxonomy.where(project_model:, name: options[:type])
        end

        raise ActiveRecord::RecordNotFound if types.empty?

        types.each_with_index do |type, idx|
          puts "#{idx + 1} of #{types.count} - #{type.name}"
          type_p = type.name.parameterize
          records = CoreDataConnector::Relationship.where(related_record: type).map(&:primary_record)
          geojson = CoreDataConnector::OpenGeographies::Geojson.new(records, type_p)
          geojson.write_geojson(File.join(tmp_dir, "#{type_p}.json"))
        end

        map_features_model = CoreDataConnector::ProjectModel.find_by(project: project_model.project, name: 'Map Features')

        if map_features_model
          features = map_features_model.model_class.constantize.where(
            project_model: map_features_model,
          )
          features.each do |feature|
            type_p = feature.name.parameterize
            geojson = CoreDataConnector::OpenGeographies::Geojson.new([feature], type_p)
            geojson.write_geojson(File.join(tmp_dir, "#{type_p}.json"))
          end
        end

        puts "#{types.count} GeoJSON files written!"
        puts 'Making PMTiles.'

        inputs = types.map { |type| File.join(tmp_dir, "#{type.name.parameterize}.json") }.map(&:to_s)
        extra_args = ['-zg', '-B 7', '--drop-densest-as-needed', '--extend-zooms-if-still-dropping']
        builder.build(input: inputs, output: File.join(tmp_dir, 'gca.pmtiles'), extra_args:)

        if options[:skip]
          puts 'Skipping upload and cleanup.'
        else
          puts 'Copying PMTiles file to S3.'

          s3 = Aws::S3::Resource.new(region: 'us-east-1')
          bucket = s3.bucket('ecds-pmtiles')
          begin
            obj = bucket.object('gca.pmtiles')
            obj.upload_file(File.join(tmp_dir, 'gca.pmtiles'))
            puts 'PMTiles uploaded!'
          rescue Aws::S3::Errors::ServiceError => e
            puts "S3 Upload Failed :( - #{e.message}"
            exit
          end

          cf_client = Aws::CloudFront::Client.new(region: 'us-east-1')
          distribution_id = 'E2JG3EJZ7GQA2D'
          invalidation_paths = ['/*']
          caller_reference = Time.now.to_i.to_s

          begin
            invalidation_response = cf_client.create_invalidation(
              {
                distribution_id:,
                invalidation_batch: {
                  paths: {
                    quantity: invalidation_paths.length,
                    items: invalidation_paths,
                  },
                  caller_reference: caller_reference,
                },
              },
            )

            puts 'Invalidation request submitted successfully.'
            puts "Invalidation ID: #{invalidation_response.invalidation.id}"
            puts "Status: #{invalidation_response.invalidation.status}"
          rescue Aws::CloudFront::Errors::ServiceError => e
            puts "Error creating invalidation: #{e.message}"
          end
          FileUtils.rm_rf(tmp_dir)
        end
        exit
      end
    end
  end
end
