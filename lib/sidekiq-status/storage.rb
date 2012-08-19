module Sidekiq::Status::Storage
  RESERVED_FIELDS=%w(status stop update_time).freeze

  protected

  # Stores multiple values into a job's status hash,
  # sets last update time
  # @param [String] id job id
  # @param [Hash] status_updates updated values
  # @return [String] Redis operation status code
  def store_for_id(id, status_updates)
    Sidekiq.redis do |conn|
      answers = conn.multi do
        conn.hmset id, 'update_time', Time.now.to_i, *(status_updates.to_a.flatten)
        conn.expire id, Sidekiq::Status::DEFAULT_EXPIRY
        conn.publish "status_updates", id
      end
      answers[0]
    end
  end

  # Gets a single valued from job status hash
  # @param [String] id job id
  # @param [String] Symbol field fetched field name
  # @return [String] Redis operation status code
  def read_field_for_id(uuid, field)
    Sidekiq.redis do |conn|
      conn.hmget(uuid, field)[0]
    end
  end
end