module Sidekiq::Status::Storage
  RESERVED_FIELDS=%w(status stop update_time).freeze

  protected

  # Stores multiple values into a job's status hash,
  # sets last update time
  # @param [String] id job id
  # @param [Hash] status_updates updated values
  # @return [String] Redis operation status code
  def store_for_id(id, status_updates, expiration = nil)
    Sidekiq.redis do |conn|
      conn.multi do
        conn.hmset  id, 'update_time', Time.now.to_i, *(status_updates.to_a.flatten)
        conn.expire id, (expiration || Sidekiq::Status::DEFAULT_EXPIRY)
        conn.publish "status_updates", id
      end[0]
    end
  end

  # Stores job status and sets expiration time to it
  # only in case of :failed or :stopped job
  # @param [String] id job id
  # @param [Symbol] job status
  # @return [String] Redis operation status code
  def store_status(id, status, expiration = nil)
    store_for_id id, {status: status}, expiration
  end

  # Gets a single valued from job status hash
  # @param [String] id job id
  # @param [String] Symbol field fetched field name
  # @return [String] Redis operation status code
  def read_field_for_id(id, field)
    Sidekiq.redis do |conn|
      conn.hmget(id, field)[0]
    end
  end

  # Gets the whole status hash from the job status
  # @param [String] id job id
  # @return [Hash] Hash stored in redis
  def read_hash_for_id(id)
    Sidekiq.redis do |conn|
      conn.hgetall id
    end
  end
end
