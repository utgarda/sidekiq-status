require "sidekiq-status/version"
require 'sidekiq-status/storage'
require 'sidekiq-status/worker'
require 'sidekiq-status/client_middleware'

module Sidekiq
  module Status
    DEFAULT_EXPIRY = 60 * 30
  end
end
