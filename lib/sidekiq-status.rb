require 'sidekiq-status/version'
require 'sidekiq-status/sidekiq_extensions'
require 'sidekiq-status/storage'
require 'sidekiq-status/worker'
require 'sidekiq-status/client_middleware'
require 'sidekiq-status/server_middleware'
require 'sidekiq-status/web' if defined?(Sidekiq::Web)
require 'chronic_duration'

module Sidekiq::Status
  extend Storage
  DEFAULT_EXPIRY = 60 * 30
  STATUS = [ :queued, :working, :retrying, :complete, :stopped, :failed, :interrupted ].freeze

  class << self
    # Job status by id
    # @param [String] id job id returned by async_perform
    # @return [String] job status, possible values are in STATUS
    def get(job_id, field)
      read_field_for_id(job_id, field)
    end

    # Get all status fields for a job
    # @params [String] id job id returned by async_perform
    # @return [Hash] hash of all fields stored for the job
    def get_all(job_id)
      read_hash_for_id(job_id)
    end

    def status(job_id)
      status = get(job_id, :status)
      status.to_sym  unless status.nil?
    end

    def cancel(job_id, job_unix_time = nil)
      delete_and_unschedule(job_id, job_unix_time)
    end

    def delete(job_id)
      delete_status(job_id)
    end

    alias_method :unschedule, :cancel

    STATUS.each do |name|
      define_method("#{name}?") do |job_id|
        status(job_id) == name
      end
    end

    # Methods for retrieving job completion
    def at(job_id)
      get(job_id, :at).to_i
    end

    def total(job_id)
      get(job_id, :total).to_i
    end

    def pct_complete(job_id)
      get(job_id, :pct_complete).to_i
    end

    def message(job_id)
      get(job_id, :message)
    end
  end
end
