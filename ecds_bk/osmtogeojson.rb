# frozen_string_literal: true

class Osmtogeojson
  def initialize(query, retries = 10)
    @query = query
    @tmp_file = Tempfile.new(['', '.json'], binmode: true)
    @attempts = 0
    @retries = retries
    @binary = 'osmtogeojson'
    ensure_installed!
  end

  def convert
    overpass
    out, err, status = Open3.capture3(@binary, @tmp_file.path)
    @tmp_file.delete
    return JSON.parse(out, symbolize_names: true) if status.success?

    raise StandardError, err.strip
  end

  private

  # Check osmtogeojson availability
  def installed?
    system("#{@binary} --version > /dev/null 2>&1")
  end

  def ensure_installed!
    raise NotInstalledError, "tippecanoe binary not found at '#{@binary}'" unless installed?
  end

  def overpass
    @attempts += 1
    begin
      response = HTTParty.post('https://overpass-api.de/api/interpreter', body: @query)
      if response.success?
        @tmp_file.write(response.body)
        @tmp_file.close
      elsif @attempts < @retries
        puts "retrying in #{@attempts}"
        sleep(@attempts)
        overpass
      else
        raise HTTParty::ResponseError, response unless response.success?
      end
    rescue Net::OpenTimeout
      puts "attempt #{@attempts}"
      overpass if @attempts < @retries
    end
  end
end
