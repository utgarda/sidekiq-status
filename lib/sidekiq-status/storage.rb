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
        conn.hmset  id, 'update_time', Time.now.to_i, *(status_updates.to_a.flatten(1))
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

  # Unschedules the job and deletes the Status
  # @param [String] id job id
  # @param [Num] job_unix_time, unix timestamp for the scheduled job
  def delete_and_unschedule(job_id, job_unix_time = nil)
    Sidekiq.redis do |conn|
      scheduled_jobs = conn.zrange "schedule", 0, -1, {withscores: true}
      matching_index = scan_scheduled_jobs_for_jid scheduled_jobs, job_id, job_unix_time

      job_found = matching_index > -1
      if job_found
        conn.zrem "schedule", scheduled_jobs[matching_index]
        conn.del job_id
      end
      job_found
    end
  end

  # Searches the schedule Array for the job_id
  # @param [Array] scheduled_jobs, results of Redis schedule key
  # @param [String] id job id
  # @param [Num] job_unix_time, unix timestamp for the scheduled job
  def scan_scheduled_jobs_for_jid(scheduled_jobs, job_id, job_unix_time = nil)
    ## schedule is an array ordered by a (float) unix timestamp for the posting time.
    ## Better would be to binary search on the time: # jobs_same_time = scheduled_jobs.bsearch {|x| x[1] == unix_time_scheduled }
    ## Unfortunately Ruby 2.0's bsearch won't help here because it does not return a range of elements (would only return first-matching), nor does it return an index.
    ## Instead we will scan through all elements until timestamp matches and check elements after:
    scheduled_jobs.each_with_index do |schedule_listing, i|
      checking_result = listing_matches_job(schedule_listing, job_id, job_unix_time)
      if checking_result.nil?
        return -1 # Is nil when we've exhaused potential candidates
      elsif checking_result
        return i
      end
    end
    -1 # Not found
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

  private

  # Searches the schedule Array for the job_id
  # @param [Array] schedule_listing, a particular entry from the Redis schedule Array
  # @param [String] id job id
  # @param [Num] job_unix_time, unix timestamp for the scheduled job
  def listing_matches_job(schedule_listing, job_id, job_unix_time = nil)
    if(job_unix_time.nil? || schedule_listing[1] == job_unix_time)
      # A Little skecthy, I know, but the structure of these internal JSON
      # is predefined in such a way where this will not catch unintentional elements,
      # and this is notably faster than performing JSON.parse() for every listing:
      if schedule_listing[0].include?("\"jid\":\"#{job_id}")
        return true
      end
    elsif(schedule_listing[1] > job_unix_time)
      return nil #Not found. Can break (due to ordering)
    end
    false
  end
end
