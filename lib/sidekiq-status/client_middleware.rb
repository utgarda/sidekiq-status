module Sidekiq::Status
# Should be in the client middleware chain
  class ClientMiddleware
    include Storage
    # Uses msg['jid'] id and puts :queued status in the job's Redis hash
    # @param [Class] worker_class if includes Sidekiq::Status::Worker, the job gets processed with the plugin
    # @param [Array] msg job arguments
    # @param [String] queue the queue's name
    def call(worker_class, msg, queue, redis_pool=nil)
      store_status msg['jid'], :queued, nil, redis_pool
      yield
    end
  end
end
