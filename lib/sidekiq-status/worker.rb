module Sidekiq::Status::Worker
  include Sidekiq::Status::Storage

  class Stopped < StandardError
  end

  attr_accessor :expiration

  # Stores multiple values into a job's status hash,
  # sets last update time
  # @param [Hash] status_updates updated values
  # @return [String] Redis operation status code
  def store(hash)
    store_for_id @jid, hash, @expiration
  end

  # Read value from job status hash
  # @param String|Symbol hask key
  # @return [String]
  def retrieve(name)
    read_field_for_id @jid, name
  end

  # Sets current task progress
  # (inspired by resque-status)
  # @param Fixnum number of tasks done
  # @param Fixnum total number of tasks
  # @param String optional message
  # @return [String]
  def at(num, total, message=nil)
    store({at: num, total: total, message: message})
  end

end
