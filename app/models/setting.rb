# Small key/value store for app state (e.g. the last repo change seen by the webhook)
class Setting < ApplicationRecord
  def self.[](key)
    find_by(key: key)&.value
  end

  def self.[]=(key, value)
    find_or_initialize_by(key: key).update!(value: value)
  end
end
