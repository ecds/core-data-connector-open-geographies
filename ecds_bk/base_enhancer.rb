# frozen_string_literal: true

require 'elasticsearch'

module Ecds
  #
  # Base enhancer
  #
  class BaseEnhancer
    def initialize(_document)
      @client = Elasticsearch::Client.new(
        host: ENV['ELASTICSEARCH_HOST'],
        api_key: ENV['ELASTICSEARCH_API_KEY'],
        retry_on_failure: true,
        transport_options: {
          request: { timeout: 20 }
        }
      )
    end
  end
end
