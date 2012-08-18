require "sidekiq-status/version"
require 'sidekiq-status/storage'
require 'sidekiq-status/worker'
require 'sidekiq-status/client_middleware'
require 'sidekiq-status/server_middleware'

module Sidekiq
  module Status
    DEFAULT_EXPIRY = 60 * 30
    UUID_REGEXP = /[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}/
  end
end
