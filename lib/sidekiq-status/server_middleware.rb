if Sidekiq.major_version >= 5
  require 'sidekiq/job_retry'
end

module Sidekiq::Status
  # Should be in the server middleware chain
  class ServerMiddleware

    DEFAULT_MAX_RETRY_ATTEMPTS = Sidekiq.major_version >= 5 ? Sidekiq::JobRetry::DEFAULT_MAX_RETRY_ATTEMPTS : 25

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

      # Initial assignment to prevent SystemExit & co. from excepting
      expiry = @expiration

      # Determine the actual job class
      klass = msg["args"][0]["job_class"] || msg["class"] rescue msg["class"]
      job_class = klass.is_a?(Class) ? klass : Module.const_get(klass)

      # Bypass unless this is a Sidekiq::Status::Worker job
      unless job_class.ancestors.include?(Sidekiq::Status::Worker)
        yield
        return
      end

      # Determine job expiration
      expiry = job_class.new.expiration || @expiration rescue @expiration

      store_status worker.jid, :working,  expiry
      yield
      store_status worker.jid, :complete, expiry
    rescue Worker::Stopped
      store_status worker.jid, :stopped, expiry
    rescue SystemExit, Interrupt
      store_status worker.jid, :interrupted, expiry
      raise
    rescue Exception
      status = :failed
      if msg['retry']
        if retry_attempt_number(msg) < retry_attempts_from(msg['retry'], DEFAULT_MAX_RETRY_ATTEMPTS)
          status = :retrying
        end
      end
      store_status worker.jid, status, expiry
      raise
    end

    private

    def retry_attempt_number(msg)
      if msg['retry_count']
        msg['retry_count'] + sidekiq_version_dependent_retry_offset
      else
        0
      end
    end

    def retry_attempts_from(msg_retry, default)
      msg_retry.is_a?(Integer) ? msg_retry : default
    end

    def sidekiq_version_dependent_retry_offset
      Sidekiq.major_version >= 4 ? 1 : 0
    end
  end

  # Helper method to easily configure sidekiq-status server middleware
  # whatever the Sidekiq version is.
  # @param [Sidekiq] sidekiq_config the Sidekiq config
  # @param [Hash] server_middleware_options server middleware initialization options
  # @option server_middleware_options [Fixnum] :expiration ttl for complete jobs
  def self.configure_server_middleware(sidekiq_config, server_middleware_options = {})
    sidekiq_config.server_middleware do |chain|
      if Sidekiq.major_version < 5
        chain.insert_after Sidekiq::Middleware::Server::Logging,
          Sidekiq::Status::ServerMiddleware, server_middleware_options
      else
        chain.add Sidekiq::Status::ServerMiddleware, server_middleware_options
      end
    end

  end
end
