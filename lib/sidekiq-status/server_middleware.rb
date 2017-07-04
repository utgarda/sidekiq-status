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
      # and it allows also to overwrite global expiration time on worker basis
      if worker.respond_to? :expiration
        if !worker.expiration && worker.respond_to?(:expiration=)
          worker.expiration = @expiration
        else
          @expiration = worker.expiration
        end
      end
      Sidekiq.logger.info 1
      store_status worker.jid, :working, worker.class.to_s, @expiration
      yield
      store_status worker.jid, :complete, worker.class.to_s, @expiration

    rescue Worker::Stopped
      store_status worker.jid, :stopped, worker.class.to_s, @expiration
    rescue SystemExit, Interrupt
      store_status worker.jid, :interrupted, worker.class.to_s, @expiration
      raise
    rescue
      store_status worker.jid, :failed, worker.class.to_s, @expiration
      raise
    end
  end
end
