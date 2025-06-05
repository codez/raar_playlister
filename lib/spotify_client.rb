require 'base64'

class SpotifyClient
  MAX_TRACKS = 100
  MAX_PAGE_SIZE = 50

  attr_reader :settings, :logger

  def initialize(settings, logger)
    @settings = settings
    @logger = logger
  end

  def assert_playlist(name)
    get_playlist(name) || create_playlist(name)
  end

  def search_song(title, artist)
    query = CGI.escape("#{normalize_title(title)} artist:#{artist}")
    api_request(:get, "search?type=track&limit=3&q=#{query}")
      .dig('tracks', 'items')
      .first || log_no_song(title, artist)
  end

  def fetch_playlist_song_uris(playlist_id)
    get_paginated("playlists/#{playlist_id}/tracks?fields=items(track(uri))&")
      .map { |item| item.dig('track', 'uri') }
  end

  def clear_playlist(playlist_id)
    api_request(:put, "playlists/#{playlist_id}/tracks", { uris: [] })
  end

  def add_songs_to_playlist(playlist_id, uris, position = nil)
    logger.info("Adding #{uris.size} tracks...") unless uris.empty?
    uris.each_slice(MAX_TRACKS) do |batch|
      body = { uris: batch, position: position }
      api_request(:post, "playlists/#{playlist_id}/tracks", body)
      position += MAX_TRACKS if position
    end
  end

  def remove_songs_from_playlist(playlist_id, uris)
    logger.info("Removing #{uris.size} tracks...") unless uris.empty?
    uris.each_slice(MAX_TRACKS) do |batch|
      body = { tracks: batch.map { |uri| { uri: uri } } }
      api_request(:delete, "playlists/#{playlist_id}/tracks", body)
    end
  end

  def login
    params = {
      response_type: 'code',
      client_id: settings.fetch('client_id'),
      scope: 'playlist-modify-public',
      redirect_uri: CGI.escape(settings.fetch('redirect_uri'))
    }.map { |k, v| "#{k}=#{v}" }.join('&')

    system "open 'https://accounts.spotify.com/authorize?#{params}'"
  end

  def fetch_refresh_token(code)
    token_request(
      code: code,
      grant_type: 'authorization_code',
      redirect_uri: settings['redirect_uri']
    ).fetch('refresh_token')
  end

  private

  def get_playlist(name)
    get_paginated("users/#{user_id}/playlists?") do |items|
      match = items.find { |playlist| playlist['name'] == name }
      return match if match
    end
    nil
  end

  def get_paginated(path, offset = 0)
    items = api_request(:get, "#{path}limit=#{MAX_PAGE_SIZE}&offset=#{offset}").fetch('items')
    yield items if block_given?
    items + (items.size < MAX_PAGE_SIZE ? [] : get_paginated(path, offset + MAX_PAGE_SIZE))
  end

  def create_playlist(name)
    logger.info("Creating playlist #{name}")
    api_request(:post, "users/#{user_id}/playlists", { name: name, description: '' })
  end

  def log_no_song(title, artist)
    logger.debug("Could not find song '#{title}' by #{artist}")
    nil
  end

  def user_id
    settings.fetch('user_id')
  end

  def normalize_title(title)
    # - remove everything in brackets (e.g. extended mix)
    # - remove feat. (appears more likely in artists)
    title
      .gsub(/\(.+?\)/, '')
      .gsub(/\[.+?\]/, '')
      .split('feat.').first
  end

  def access_token
    @access_token ||= fetch_access_token
  end

  def fetch_access_token
    token_request(
      refresh_token: settings['refresh_token'],
      grant_type: 'refresh_token'
    ).fetch('access_token')
  end

  def api_request(method, path, body = nil)
    response = RestClient::Request.execute(
      method: method,
      url: "https://api.spotify.com/v1/#{path}",
      payload: body&.to_json,
      headers: { Authorization: "Bearer #{access_token}" }
    )
    JSON.parse(response.body)
  rescue RestClient::ExceptionWithResponse => e
    logger.error("#{e}\n#{e.response.body}")
    raise e
  end

  def token_request(data)
    response = RestClient.post(
      'https://accounts.spotify.com/api/token',
      data,
      Authorization: basic_client_auth
    )
    JSON.parse(response.body)
  end

  def basic_client_auth
    credentials = "#{settings.fetch('client_id')}:#{settings.fetch('client_secret')}"
    "Basic #{Base64.strict_encode64(credentials)}"
  end
end
