module Sidekiq::Status::Worker
  include Sidekiq::Status::Storage

  class Stopped < StandardError
  end

  # Stores multiple values into a job's status hash,
  # sets last update time
  # @param [Hash] status_updates updated values
  # @return [String] Redis operation status code
  def store(hash)
    store_for_id @jid, hash
  end

  def at(num, total, message=nil)
    store_for_id @jid, {num: num, total: total, message: message}
  end

end
