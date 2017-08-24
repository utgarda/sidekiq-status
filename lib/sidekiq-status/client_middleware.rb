require 'sidekiq/api'
module Sidekiq::Status
# Should be in the client middleware chain
  class ClientMiddleware
    include Storage

    # Parameterized initialization, use it when adding middleware to client chain
    # chain.add Sidekiq::Status::ClientMiddleware, :expiration => 60 * 5
    # @param [Hash] opts middleware initialization options
    # @option opts [Fixnum] :expiration ttl for complete jobs
    def initialize(opts = {})
      @expiration = opts[:expiration]
      @all_jobs = opts.fetch(:all_jobs, true)
    end

    # Uses msg['jid'] id and puts :queued status in the job's Redis hash
    # @param [Class] worker_class if includes Sidekiq::Status::Worker, the job gets processed with the plugin
    # @param [Array] msg job arguments
    # @param [String] queue the queue's name
    # @param [ConnectionPool] redis_pool optional redis connection pool
    def call(worker_class, msg, queue, redis_pool=nil)
      if @all_jobs || need_status?(worker_class)
        initial_metadata = {
          jid: msg['jid'],
          status: :queued,
          worker: worker_class,
          args: display_args(msg, queue)
        }
        store_for_id msg['jid'], initial_metadata, @expiration, redis_pool
      end

      yield
    end

    private

    def display_args(msg, queue)
      job = Sidekiq::Job.new(msg, queue)
      return job.display_args.to_a.empty? ? nil : job.display_args.to_json
    rescue Exception => e
      # For Sidekiq ~> 2.7
      return msg['args'].to_a.empty? ? nil : msg['args'].to_json
    end

    def need_status?(worker_class)
      Object.const_get(worker_class).ancestors.include?(Sidekiq::Status::Worker)
    end
  end
end
