module Sidekiq
  module Status
    class << self
      def status(_jid)
        :complete
      end
    end
  end
end
