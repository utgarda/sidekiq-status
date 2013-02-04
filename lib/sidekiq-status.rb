require "sidekiq-status/version"
require 'sidekiq-status/storage'
require 'sidekiq-status/worker'
require 'sidekiq-status/client_middleware'
require 'sidekiq-status/server_middleware'

module Sidekiq
  module Status
    extend Storage
    DEFAULT_EXPIRY = 60 * 30
    STATUS = %w(queued working complete stopped failed).map(&:to_sym).freeze

    [:status, :num, :total, :message].each do |name|
      class_eval(<<-END, __FILE__, __LINE__)
        def #{name}(job_id)
          read_field_for_id job_id, :#{name}
        end
      END
    end

    STATUS.each do |name|
      class_eval(<<-END, __FILE__, __LINE__)
        def #{name}?(job_id)
          get(job_id).to_sym == :#{name}
        end
      END
    end

    # TODO make #get synonym to #read_field_for_id and use #status instead of #get
    # Job status by id
    # @param [String] id job id returned by async_perform
    # @return [String] job status, possible values are in STATUS
    def self.get(id)
      read_field_for_id(id, :status)
    end

    def self.pct_complete(id)
      (num / total) * 100
    end

    # Get all status fields for a job
    # @params [String] id job id returned by async_perform
    # @return [Hash] hash of all fields stored for the job
    def self.get_all(id)
      read_hash_for_id(id)
    end
  end
end
