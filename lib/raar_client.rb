class RaarClient
  JSON_API_CONTENT_TYPE = 'application/vnd.api+json'.freeze

  attr_reader :settings

  def initialize(settings, logger)
    @settings = settings
    @logger = logger
  end

  def fetch_latest_tracks_of_show(show_id, number_of_tracks)
    fetch_show_tracks(show_id, number_of_tracks).map do |track|
      track['attributes'].slice('title', 'artist')
    end
  end

  def fetch_latest_broadcast_tracks(show_id, number_of_broadcasts, weekday = nil)
    find_broadcasts(show_id, number_of_broadcasts, weekday).flat_map do |broadcast|
      fetch_broadcast_tracks(broadcast['id']).map do |track|
        track['attributes'].slice('title', 'artist')
      end
    end
  end

  def fetch_show(show_id)
    get_json_request("shows/#{show_id}")['attributes']
  end

  def search_show(title)
    get_json_request("shows?q=#{CGI.escape(title)}")
      .find { |show| show['attributes']['name'] == title } ||
      raise("Could not find show '#{title}'")
  end

  def find_broadcasts(show_id, number_of_broadcasts, weekday = nil)
    if weekday
      fetch_broadcasts(show_id, number_of_broadcasts * 7)
        .select { |b| Date.parse(b['attributes']['started_at']).wday == weekday }
        .take(number_of_broadcasts)
    else
      fetch_broadcasts(show_id, number_of_broadcasts)
    end
  end

  def fetch_broadcasts(show_id, page_size)
    get_json_request(
      "broadcasts?show_id=#{show_id}&sort=-started_at&page[size]=#{page_size}"
    )
  end

  def fetch_show_tracks(show_id, number_of_tracks)
    get_json_request(
      "tracks?show_id=#{show_id}&sort=-started_at&page[size]=#{number_of_tracks}"
    )
  end

  def fetch_broadcast_tracks(broadcast_id)
    get_json_request(
      "tracks?broadcast_id=#{broadcast_id}&sort=started_at&page[size]=500"
    )
  end

  private

  def get_json_request(path)
    response = raar_request(:get, path, accept: JSON_API_CONTENT_TYPE)
    json = JSON.parse(response.body)
    json['data']
  end

  def raar_request(method, path, headers = {})
    RestClient::Request.execute(
      raar_http_options.merge(
        method: method,
        url: "#{settings['url']}/#{path}",
        headers: headers
      )
    )
  end

  def raar_http_options
    @raar_http_options ||=
      (settings['options'] || {})
      .transform_keys(&:to_sym)
  end
end
