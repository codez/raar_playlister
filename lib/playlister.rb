require 'json'
require 'yaml'
require 'rest-client'
require_relative 'spotify_client'
require_relative 'raar_client'

class Playlister
  WEEKDAYS = {
    'Montag' => 1,
    'Dienstag' => 2,
    'Mittwoch' => 3,
    'Donnerstag' => 4,
    'Freitag' => 5,
    'Samstag' => 6,
    'Sonntag' => 7
  }

  def run
    # RestClient.log = logger
    each_show do |show, weekday|
      tracks = fetch_latest_tracks(show, weekday)
      update_playlist(show, weekday, tracks)
    end
  end

  private

  def each_show
    settings.dig('playlister', 'shows').each do |value|
      name, weekday = value.is_a?(Array) ? value : [value, nil]
      yield raar_client.search_show(name), weekday
    end
  end

  def fetch_latest_tracks(show, weekday)
    logger.debug("Fetching tracks for show #{show.dig('attributes', 'name')} #{weekday}")
    raar_client.fetch_latest_broadcast_tracks(
      show.fetch('id'),
      settings.dig('playlister', 'number_of_broadcasts'),
      weekday && WEEKDAYS.fetch(weekday)
    )
  end

  def update_playlist(show, weekday, tracks)
    name = playlist_name(show, weekday)
    details = show.dig('attributes', 'details')
    playlist = spotify_client.assert_playlist(name, details)
    spotify_client.add_tracks_to_playlist(playlist.fetch('id'), tracks)
  end

  def playlist_name(show, weekday)
    [
      settings.dig('playlister', 'name_prefix'),
      show.dig('attributes', 'name'),
      weekday
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
