module Sidekiq::Status::Storage
  RESERVED_FIELDS=%w(status stop update_time).freeze
  BATCH_LIMIT = 500

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
      scan_options = {offset: 0, conn: conn, start: (job_unix_time || '-inf'), end: (job_unix_time || '+inf')}

      while not (jobs = schedule_batch(scan_options)).empty?
        match = scan_scheduled_jobs_for_jid jobs, job_id
        unless match.nil?
          conn.zrem "schedule", match
          conn.del job_id
          return true # Done
        end
        scan_options[:offset] += BATCH_LIMIT
      end
    end
    false
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

  # Gets the batch of scheduled jobs based on input options
  # Uses Redis zrangebyscore for log(n) search, if unix-time is provided
  # @param [Hash] options, options hash containing (REQUIRED) keys:
  #  -  conn: Redis connection
  #  -  start: start score (i.e. -inf or a unix timestamp)
  #  -  end: end score (i.e. +inf or a unix timestamp)
  #  -  offset: current progress through (all) jobs (e.g.: 100 if you want jobs from 100 to BATCH_LIMIT)
  def schedule_batch(options)
    options[:conn].zrangebyscore "schedule", options[:start], options[:end], {limit: [options[:offset], BATCH_LIMIT]}
  end

  # Searches the jobs Array for the job_id
  # @param [Array] scheduled_jobs, results of Redis schedule key
  # @param [String] id job id
  def scan_scheduled_jobs_for_jid(scheduled_jobs, job_id)
    # A Little skecthy, I know, but the structure of these internal JSON
    # is predefined in such a way where this will not catch unintentional elements,
    # and this is notably faster than performing JSON.parse() for every listing:
    scheduled_jobs.each { |job_listing| (return job_listing) if job_listing.include?("\"jid\":\"#{job_id}") }
    nil
  end
end
