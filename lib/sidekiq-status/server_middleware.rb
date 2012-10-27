module Sidekiq::Status
# Should be in the server middleware chain
  class ServerMiddleware
    # Parameterized initialization, use it when adding middleware to server chain
    # chain.add Sidekiq::Status::ServerMiddleware, :expiration => 60 * 5
    # @param [Hash] opts middleware initialization options
    # @option opts [Fixnum] :expiration ttl for complete jobs
    def initialize(opts = {:expiration => 30 * 60})
      @expiration = opts[:expiration]
    end

    # Uses sidekiq's internal jid as id
    # puts :working status into Redis hash
    # initializes worker instance with id
    #
    # Exception handler sets :failed status, re-inserts worker and re-throws the exception
    # Worker::Stopped exception type are processed separately - :stopped status is set, no re-throwing
    #
    # @param [Worker] worker worker instance, processed here if its class includes Status::Worker
    # @param [Array] msg job args, should have jid format
    # @param [String] queue queue name
    def call(worker, msg, queue)
      if worker.is_a? Worker
        worker.id = msg['jid']
        unless worker.id.is_a?(String) && UUID_REGEXP.match(worker.id)
          raise ArgumentError, "First job argument for a #{worker.class.name} should have jid format"
        end
        worker.store 'status' => 'working'
        yield
        worker.store 'status' => 'complete'
      else
        yield
      end
    rescue Worker::Stopped
      worker.store 'status' => 'stopped'
    rescue
      if worker.is_a? Worker
        worker.store 'status' => 'failed'
      end
      raise
    ensure
      Sidekiq.redis { |conn| conn.expire worker.id, @expiration } if worker.is_a? Worker
    end
  end
end
