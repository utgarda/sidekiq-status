module Sidekiq::Status::Worker
  include Sidekiq::Status::Storage

  class Stopped < StandardError
  end

  attr_reader :id

  # Worker id initialization
  # @param [String] id id generated on client-side
  # @raise [RuntimeError] raised in case of second id initialization attempt
  # @return [String] id
  def id=(id)
    raise RuntimeError("Worker ID is already set : #{@id}") if @id
    @id=id
  end

  # Stores multiple values into a job's status hash,
  # sets last update time
  # @param [Hash] status_updates updated values
  # @return [String] Redis operation status code
  def store(hash)
    store_for_id(@id, hash)
  end

end