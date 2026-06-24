# frozen_string_literal: true

source 'https://rubygems.org'

# Specify your gem's dependencies in core-data-connector-ecds.gemspec.
gemspec

gem 'puma'

gem 'propshaft'

# Resource API
gem 'resource_api', git: 'https://github.com/performant-software/resource-api.git', tag: 'v0.5.15'

# IIIF
gem 'triple_eye_effable', git: 'https://github.com/performant-software/triple-eye-effable.git', tag: 'v0.2.7'

# User defined fields
gem 'user_defined_fields', git: 'https://github.com/performant-software/user-defined-fields.git', tag: 'v0.1.14'

# Fuzzy dates
gem 'fuzzy_dates', git: 'https://github.com/performant-software/fuzzy-dates.git', tag: 'v0.1.2'

# Core data
gem 'core_data_connector', git: 'https://github.com/performant-software/core-data-connector.git', tag: 'v0.1.103'

# Elasticsearch
gem 'elasticsearch', '~> 8.0'
gem 'faraday-typhoeus', '~> 1.0' # Needed to use Elasticsearch in rake tasks.
gem 'searchkick'

# Geospatial libraries
gem 'aws-sdk'
gem 'concurrent-ruby', '1.3.4'
gem 'rgeo', '~> 3.0'
gem 'rgeo-geojson', '~> 2.2'

group :development, :test do
  gem 'csv', '~> 3.3.5'
  gem 'database_cleaner'
  gem 'factory_bot_rails'
  gem 'faker'
  gem 'jwt_auth', git: 'https://github.com/performant-software/jwt-auth.git', tag: 'v0.1.3'
  gem 'pg', '~> 1.5.9'
  gem 'roo', '~> 2.10.0'
  gem 'rspec-rails', '~> 8.0' # Use an appropriate version, check RSpec documentation
  gem 'rubocop-shopify'
  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem 'rubocop-rails-omakase', require: false
end
