class Show < Data.define(:id, :name, :weekday)
  WEEKDAYS = {
    'Montag' => 1,
    'Dienstag' => 2,
    'Mittwoch' => 3,
    'Donnerstag' => 4,
    'Freitag' => 5,
    'Samstag' => 6,
    'Sonntag' => 7
  }.freeze

  class << self
    def from_raar(show, weekday)
      new(
        id: show.fetch('id'),
        name: show.dig('attributes', 'name'),
        weekday: weekday
      )
    end
  end

  def full_name
    "#{name} #{weekday}".strip
  end

  def wday
    weekday && WEEKDAYS.fetch(weekday)
  end
end
