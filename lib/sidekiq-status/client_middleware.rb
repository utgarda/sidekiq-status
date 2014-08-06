module Sidekiq
  module Status
    # Should be in the client middleware chain
    class ClientMiddleware
      include Storage
      # Uses msg['jid'] id and puts :queued status in the job's Redis hash
      # @param [Class] worker_class if includes Sidekiq::Status::Worker, the job gets processed with the plugin
      # @param [Array] msg job arguments
      # @param [String] queue the queue's name
      # @param [ConnectionPool] redis_pool optional redis connection pool
      def call(*args)
        store_status args[1]['jid'], :queued, nil, args[3]
        yield
      end
    end
  end
end
