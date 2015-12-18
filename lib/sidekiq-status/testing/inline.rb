module Sidekiq
  module Status
    class << self
      def status(jid)
        :complete
      end
    end
  end
  
  module Storage
    def store_status(id, status, expiration = nil, redis_pool=nil)
      'ok'
    end
  end
end

