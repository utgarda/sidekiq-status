require "sidekiq-status/version"
require 'sidekiq-status/storage'
require 'sidekiq-status/worker'
require 'sidekiq-status/client_middleware'
require 'sidekiq-status/server_middleware'

module Sidekiq
  module Status
    extend Storage
    DEFAULT_EXPIRY = 60 * 30
    UUID_REGEXP = /[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}/

    # Job status by id
    # @param [String] id job id returned by async_perform
    # @return [String] job status, possible values: "queued" , "working" , "complete"
    def self.get(id)
      read_field_for_id(id, :status)
    end

    # Get all status fields for a job
    # @params [String] id job id returned by async_perform
    # @return [Hash] hash of all fields stored for the job
    def self.get_all(id)
      read_hash_for_id(id)
    end
  end
end
