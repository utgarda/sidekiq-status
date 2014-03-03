module Sidekiq::Status
# Should be in the server middleware chain
  class ServerMiddleware
    include Storage

    # Parameterized initialization, use it when adding middleware to server chain
    # chain.add Sidekiq::Status::ServerMiddleware, :expiration => 60 * 5
    # @param [Hash] opts middleware initialization options
    # @option opts [Fixnum] :expiration ttl for complete jobs
    def initialize(opts = {})
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
      # a way of overriding default expiration time,
      # so worker wouldn't lose its data
      worker.expiration = @expiration  if worker.respond_to? :expiration=

      store_status worker.jid, :working,  @expiration
      yield
      store_status worker.jid, :complete, @expiration
    rescue Worker::Stopped
      store_status worker.jid, :stopped, @expiration
    rescue
      store_status worker.jid, :failed,  @expiration
      raise
    end
  end
end
