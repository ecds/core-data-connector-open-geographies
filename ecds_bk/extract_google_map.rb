#!/usr/bin/env ruby
# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'nokogiri'
require 'cgi'

# URL to scrape
# url = 'https://www.hrcga.org/church/grace-episcopal/'

module Ecds
  module ExtractGoogleMap
    def self.extract_google_maps_query(url)
      doc = fetch_page(url)

      # Find all iframes
      iframes = doc.css('iframe').to_ary

      # Filter for Google Maps iframes
      iframes.select! do |iframe|
        src = iframe[:src]
        src && (src.include?('google.com/maps') || src.include?('maps.google.com'))
      end

      iframes.map { |f| parse_iframe(f) }
    end

    def self.extract_more_content(url)
      doc = fetch_page(url)
      links = []

      # Find the "More Content" heading
      more_content_heading = doc.xpath("//h3[contains(text(), 'More Content')]").first

      if more_content_heading
        # Get the next sibling elements after the heading
        # Look for links in the immediate following paragraph or div
        next_element = more_content_heading.next_element

        while next_element && next_element.name != 'h2' && next_element.name != 'h3'
          # Find all links in this element
          next_element.css('a').each do |link|
            href = link['href']
            text = link.text.strip

            # Skip empty links or anchor links
            if href && !href.empty? && !href.start_with?('#')
              links << { text: text, url: href }
            end
          end

          next_element = next_element.next_element

          # Stop if we've found links and moved past the links section
          break if links.any? && next_element && next_element.name =~ /^h[1-6]$/
        end
      end

      links
    end

    def self.extract_organized_year(url)
      doc = fetch_page(url)

      # Look for h3 elements that contain "Organized in"
      h3_elements = doc.css('h3')

      h3_elements.each do |h3|
        text = h3.text.strip

        # Check if this h3 contains "Organized in"
        if text =~ /Organized in/i
          # Extract the year after "Organized in"
          if text =~ /Organized in\s+(\d{4})/i
            return ::Regexp.last_match(1)
          end
        end
      end

      nil
    end

    def self.extract_photographer(url)
      doc = fetch_page(url)

      # Search through all text nodes for "Photography by" or "Photograph by"
      # Check common containers like paragraphs, divs, spans
      element = doc.xpath("//div[contains(text(), 'Photography by')]").first

      text = element.text.strip

      # Check for "Photography by" or "Photograph by" (case insensitive)
      if text =~ /(Photography|Photograph)\s+by\s+(.+)/i
        return ::Regexp.last_match(2).strip
      end

      nil
    end

    def self.fetch_page(uri)
      response = HTTParty.get(uri)

      if response.success?
        Nokogiri::HTML(response.body)
      else
        puts "Error fetching page: HTTP #{response.code}"
        exit(1)
      end
    end

    def self.parse_iframe(iframe)
      uri = URI.parse(iframe[:src])
      query_params = CGI.parse(uri.query).deep_symbolize_keys
      query_params[:q].first
    end

    # # Main execution
    # puts "Fetching page: #{url}"
    # html = fetch_page(url)

    # puts "\nSearching for Google Maps iframes..."
    # iframes = extract_google_maps_iframe(html)

    # if iframes.empty?
    #   puts "\nNo Google Maps iframes found on this page."
    #   puts "\nNote: The map might be loaded dynamically with JavaScript."
    #   puts "In that case, you would need a tool like Selenium to render the JavaScript."
    # else
    #   puts "\nFound #{iframes.length} Google Maps iframe(s):\n\n"

    #   iframes.each_with_index do |iframe, index|
    #     puts "=== Iframe #{index + 1} ==="
    #     puts "Full HTML:"
    #     puts iframe.to_html
    #     puts "\nSrc attribute:"
    #     puts iframe['src']
    #     puts "\n"
    #   end
    # end
  end
end
