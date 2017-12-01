require 'sidekiq/version'

module Sidekiq
  def self.major_version
    VERSION.split('.').first.to_i
  end
end
