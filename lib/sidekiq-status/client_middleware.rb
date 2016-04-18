module Sidekiq::Status
# Should be in the client middleware chain
  class ClientMiddleware
    include Storage

    # Parameterized initialization, use it when adding middleware to client chain
    # chain.add Sidekiq::Status::ClientMiddleware, :expiration => 60 * 5
    # @param [Hash] opts middleware initialization options
    # @option opts [Fixnum] :expiration ttl for complete jobs
    # @option opts [boolean] :all_jobs indicates all jobs should have status (default: true)
    def initialize(opts = {})
      default_opts = {expiration: nil, all_jobs: true}
      opts = default_opts.merge(opts)
      @expiration = opts[:expiration]
      @all_jobs = opts[:all_jobs]
    end

    # Uses msg['jid'] id and puts :queued status in the job's Redis hash
    # @param [Class] worker_class if includes Sidekiq::Status::Worker, the job gets processed with the plugin
    # @param [Array] msg job arguments
    # @param [String] queue the queue's name
    # @param [ConnectionPool] redis_pool optional redis connection pool
    def call(worker_class, msg, queue, redis_pool=nil)
      if @all_jobs || is_sidekiq_status_worker?(worker_class)
        initial_metadata = {
          jid: msg['jid'],
          status: :queued,
          worker: worker_class,
          args: msg['args'].to_a.empty? ? nil : msg['args'].to_json
        }
        store_for_id msg['jid'], initial_metadata, @expiration, redis_pool
      end
      yield
    end

    private

    def is_sidekiq_status_worker?(worker_class)
      worker_class = Module.const_get(worker_class) if worker_class.is_a?(String)
      worker_class.ancestors.include?(Sidekiq::Status::Worker)
    end
  end
end