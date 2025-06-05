require 'json'
require 'yaml'
require 'rest-client'
require_relative 'spotify_client'
require_relative 'raar_client'
require_relative 'show'
require_relative 'playlist_cache'

class Playlister

  def run # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    each_show do |show|
      broadcasts = fetch_latest_broadcasts(show)
      latest_broadcast_at = Date.parse(broadcasts.first['attributes']['started_at'])
      cache = PlaylistCache.new(show.full_name, latest_broadcast_at)
      next if cache.up_to_date?

      logger.info("Fetching tracks for show #{show.full_name}")
      cache_song_uris(broadcasts, cache)
      playlist = assert_playlist(show)
      update_playlist_tracks(playlist['id'], cache)
      cache.store!
    end
  end

  private

  def each_show
    settings.dig('playlister', 'shows').each do |value|
      name, weekday = value.is_a?(Array) ? value : [value, nil]
      yield Show.from_raar(raar_client.search_show(name), weekday)
    end
  end

  def fetch_latest_broadcasts(show)
    raar_client.find_broadcasts(
      show.id,
      settings.dig('playlister', 'number_of_broadcasts'),
      show.wday
    )
  end

  def fetch_latest_tracks(broadcasts)
    broadcasts.flat_map do |broadcast|
      raar_client.fetch_broadcast_tracks(broadcast['id'])
    end
  end

  def cache_song_uris(broadcasts, cache)
    fetch_latest_tracks(broadcasts).each do |track|
      cache.add_track(track) do
        title = track.dig('attributes', 'title')
        artist = track.dig('attributes', 'artist')
        spotify_client.search_song(title, artist)&.fetch('uri')
      end
    end
  end

  def assert_playlist(show)
    name = playlist_name(show)
    spotify_client.assert_playlist(name)
  end

  def update_playlist_tracks(playlist_id, cache)
    spotify_client.clear_playlist(playlist_id) unless cache.present?
    spotify_client.add_songs_to_playlist(playlist_id, cache.added_uids, 0)
    spotify_client.remove_songs_from_playlist(playlist_id, cache.removed_uids)
  end

  def playlist_name(show)
    [
      settings.dig('playlister', 'name_prefix'),
      show.full_name
    ].compact.join(' ')
  end

  def spotify_client
    @spotify_client ||= SpotifyClient.new(settings['spotify'], logger)
  end

  def raar_client
    @raar_client ||= RaarClient.new(settings['raar'], logger)
  end

  def settings
    @settings ||= YAML.safe_load(File.read(settings_file))
  end

  def settings_file
    File.join(File.join(__dir__), '..', 'config', 'settings.yml')
  end

  def logger
    @logger ||= create_logger.tap do |logger|
      level = settings.dig('playlister', 'log_level') || 'info'
      logger.level = Logger.const_get(level.upcase)
      # RestClient.log = logger if level == 'debug'
    end
  end

  def create_logger
    if settings.dig('playlister', 'log') == 'syslog'
      create_syslog_logger
    else
      Logger.new($stdout)
    end
  end

  def create_syslog_logger
    require 'syslog/logger'
    Syslog::Logger.new('raar-playlister').tap do |logger|
      logger.formatter = proc { |severity, _datetime, _prog, msg|
        "#{Logger::SEV_LABEL[severity]} #{msg}"
      }
    end
  end
end
