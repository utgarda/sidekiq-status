require "sidekiq-status/version"
require 'sidekiq-status/storage'
require 'sidekiq-status/worker'
require 'sidekiq-status/client_middleware'
require 'sidekiq-status/server_middleware'

module Sidekiq::Status
  extend Storage
  DEFAULT_EXPIRY = 60 * 30
  STATUS = %w(queued working complete stopped failed).map(&:to_sym).freeze

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
    def get_all(id)
      read_hash_for_id(id)
    end

    def status(job_id)
      status = get(job_id, :status)
      status.to_sym  unless status.nil?
    end

    def cancel(job_id, job_unix_time = nil)
      delete_and_unschedule(job_id, job_unix_time)
    end

    alias_method :unschedule, :cancel

    STATUS.each do |name|
      class_eval(<<-END, __FILE__, __LINE__)
        def #{name}?(job_id)
          status(job_id) == :#{name}
        end
      END
    end

    # Methods for retrieving job completion
    def num(job_id)
      get(job_id, :num).to_i
    end

    def total(job_id)
      get(job_id, :total).to_i
    end

    def pct_complete(job_id)
      (num(job_id).to_f / total(job_id)) * 100
    end

    def message(job_id)
      get(job_id, :message)
    end
  end
end
