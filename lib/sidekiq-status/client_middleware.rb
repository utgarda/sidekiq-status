module Sidekiq::Status
# Should be in the client middleware chain
  class ClientMiddleware
    include Storage
    # Uses the first argument as id and puts :queued status in the job's Redis hash
    # @param [Class] worker_class if includes Sidekiq::Status::Worker, the job gets processed with the plugin
    # @param [Array] msg job arguments, the firs one becomes the id
    # @param [String] queue the queue's name
    def call(worker_class, msg, queue)
      if worker_class.include? Worker
        store_for_id(msg['args'][0], :status => :queued)
      end
      yield
    end
  end
end
