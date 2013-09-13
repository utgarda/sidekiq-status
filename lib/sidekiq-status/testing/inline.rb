module Sidekiq
  module Status
    class << self
      def status(jid)
        :complete
      end
    end
  end
end

