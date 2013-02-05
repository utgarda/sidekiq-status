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

  # Read value from job status hash
  # @param String|Symbol hask key
  def retrieve(name)
    read_field_for_id @jid, name
  end

  # Sets current task progress
  # (inspired by resque-status)
  # @param Fixnum number of tasks done
  # @param Fixnum total number of tasks
  # @param String optional message
  def at(num, total, message=nil)
    store({num: num, total: total, message: message})
  end

end
