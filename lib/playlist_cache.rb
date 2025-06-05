class PlaylistCache

  DIRECTORY = File.join(__dir__, '..', 'cache')

  def initialize(name, latest_broadcast_at)
    @name = normalize(name)
    @latest_broadcast_at = latest_broadcast_at
    @current_track_uids = {}
  end

  def up_to_date?
    file && File.basename(file) == filename
  end

  def present?
    !cached_track_uids.empty?
  end

  def add_track(track, &block)
    id = track.fetch('id').to_i
    uid = cached_track_uids.fetch(id, &block)
    @current_track_uids[id] = uid
  end

  def added_uids
    @current_track_uids.values.compact - cached_track_uids.values
  end

  def removed_uids
    cached_track_uids.values.compact - @current_track_uids.values
  end

  def fetch_uid(track)
    track_uids[track.fetch('id').to_i] ||= yield
  end

  def store!
    FileUtils.mkdir_p(DIRECTORY)
    FileUtils.rm(file) if file
    yaml = YAML.dump(@current_track_uids)
    File.write(File.join(DIRECTORY, filename), yaml)
  end

  private

  def cached_track_uids
    @cached_track_uids ||= file ? YAML.safe_load(File.read(file)) : {}
  end

  def filename
    "#{@name}_#{@latest_broadcast_at}.yml"
  end

  def file
    return @file if defined?(@file)

    @file = Dir.glob(File.join(DIRECTORY, "#{@name}_*.yml")).max
  end

  def normalize(name)
    name
      .downcase
      .gsub('ä', 'ae')
      .gsub('ö', 'oe')
      .gsub('ü', 'ue')
      .gsub(/\W+/, '_')
  end

end
