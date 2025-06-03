require 'base64'

class SpotifyClient
  MAX_TRACKS = 100
  MAX_PLAYLISTS = 50

  attr_reader :settings, :logger

  def initialize(settings, logger)
    @settings = settings
    @logger = logger
  end

  def assert_playlist(name, description)
    get_playlist(name) || create_playlist(name, description)
  end

  def add_tracks_to_playlist(playlist_id, tracks)
    logger.debug("Searching #{tracks.size} tracks...")
    tracks.each_slice(MAX_TRACKS).with_index do |batch, index|
      method = index.zero? ? :put : :post
      uris = batch.map { |track| search_song(track)&.fetch('uri') }.compact
      logger.debug("Found some #{uris.size} songs")
      add_songs_to_playlist(method, playlist_id, uris)
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

  def get_playlist(name, offset = 0)
    path = "users/#{user_id}/playlists?limit=#{MAX_PLAYLISTS}&offset=#{offset}"
    items = api_request(:get, path).fetch('items')
    items.find { |playlist| playlist['name'] == name } ||
      (items.size < MAX_PLAYLISTS ? nil : get_playlist(name, offset + MAX_PLAYLISTS))
  end

  def create_playlist(name, description)
    logger.debug("Creating playlist #{name}")
    api_request(:post, "users/#{user_id}/playlists", { name: name, description: description })
  end

  def search_song(track)
    query = CGI.escape([track['title'], track['artist']].join(' '))
    api_request(:get, "search?type=track&q=#{query}")
      .dig('tracks', 'items')
      .first
    # .tap { |song| log_different_song(track, song) }
  end

  def log_different_song(track, song)
    if song
      song_artists = song['artists'].map { |a| a['name'] }.sort
      if song['name'].downcase != track['title'].downcase ||
         song_artists.map(&:downcase) != track['artist'].downcase.split(', ').sort
        logger.info("Found song '#{song['name']}' by #{song_artists.join(', ')} -- " \
                    "instead of '#{track['title']}' by #{track['artist']}")
      end
    else
      logger.info("Could not find song #{track['title']} by #{track['artist']}")
    end
  end

  def add_songs_to_playlist(method, playlist_id, uris)
    api_request(method, "playlists/#{playlist_id}/tracks", { uris: uris })
  end

  def user_id
    settings.fetch('user_id')
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
