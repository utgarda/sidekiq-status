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

      expiry = nil

      # Determine the actual job class
      klass = msg["args"][0]["job_class"] || msg["class"] rescue msg["class"]
      job_class = klass.is_a?(Class) ? klass : Module.const_get(klass)

      # Bypass uless this is a Sidekiq::Status::Worker job
      unless job_class.ancestors.include?(Sidekiq::Status::Worker)
        yield
        return
      end

      # Determine job expiration
      expiry = job_class.new.expiration

      store_status worker.jid, :working,  expiry || @expiration
      yield
      store_status worker.jid, :complete, expiry || @expiration
    rescue Worker::Stopped
      store_status worker.jid, :stopped, expiry || @expiration
    rescue SystemExit, Interrupt
      store_status worker.jid, :interrupted, expiry || @expiration
      raise
    rescue
      store_status worker.jid, :failed, expiry || @expiration
      raise
    end

  end
end
