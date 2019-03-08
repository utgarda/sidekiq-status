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
    end

    # Uses msg['jid'] id and puts :queued status in the job's Redis hash
    # @param [Class] worker_class if includes Sidekiq::Status::Worker, the job gets processed with the plugin
    # @param [Array] msg job arguments
    # @param [String] queue the queue's name
    # @param [ConnectionPool] redis_pool optional redis connection pool
    def call(worker_class, msg, queue, redis_pool=nil)

      # Determine the actual job class
      klass = msg["args"][0]["job_class"] || worker_class rescue worker_class
      job_class = if klass.is_a?(Class)
                    klass
                  elsif Module.const_defined?(klass)
                    Module.const_get(klass)
                  else
                    nil
                  end

      # Store data if the job is a Sidekiq::Status::Worker
      if job_class && job_class.ancestors.include?(Sidekiq::Status::Worker)
        initial_metadata = {
          jid: msg['jid'],
          status: :queued,
          worker: Sidekiq::Job.new(msg, queue).display_class,
          args: display_args(msg, queue)
        }
        store_for_id msg['jid'], initial_metadata, job_class.new.expiration || @expiration, redis_pool
      end

      yield

    end

    def display_args(msg, queue)
      job = Sidekiq::Job.new(msg, queue)
      return job.display_args.to_a.empty? ? nil : job.display_args.to_json
    rescue Exception => e
      # For Sidekiq ~> 2.7
      return msg['args'].to_a.empty? ? nil : msg['args'].to_json
    end
  end

  # Helper method to easily configure sidekiq-status client middleware
  # whatever the Sidekiq version is.
  # @param [Sidekiq] sidekiq_config the Sidekiq config
  # @param [Hash] client_middleware_options client middleware initialization options
  # @option client_middleware_options [Fixnum] :expiration ttl for complete jobs
  def self.configure_client_middleware(sidekiq_config, client_middleware_options = {})
    sidekiq_config.client_middleware do |chain|
      chain.add Sidekiq::Status::ClientMiddleware, client_middleware_options
    end
  end
end
