module Sidekiq
  module Status
    class << self
      def status(jid)
        :complete
      end
    end

    module Storage
      def store_status(id, status, expiration = nil, redis_pool=nil)
        'ok'
      end

      def store_for_id(id, status_updates, expiration = nil, redis_pool=nil)
        'ok'
      end
    end
  end
end

