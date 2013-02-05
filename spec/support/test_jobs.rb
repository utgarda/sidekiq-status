class StubJob
  include Sidekiq::Worker
  include Sidekiq::Status::Worker

  sidekiq_options 'retry' => 'false'

  def perform(*args)
  end
end

class LongJob < StubJob
  def perform(*args)
    sleep args[0] || 1
  end
end

class ConfirmationJob < StubJob
  def perform(*args)
    Sidekiq.redis do |conn|
      conn.publish "job_messages_#{jid}", "while in #perform, status = #{conn.hget jid, :status}"
    end
  end
end

class NoStatusConfirmationJob
  include Sidekiq::Worker
  def perform(id)
    Sidekiq.redis do |conn|
      conn.set "NoStatusConfirmationJob_#{id}", "done"
    end
  end
end

class FailingJob < StubJob
  def perform
    raise StandardError
  end
end

class RetriedJob < StubJob
  sidekiq_options 'retry' => 'true'
  def perform()
    Sidekiq.redis do |conn|
      key = "RetriedJob_#{jid}"
      unless conn.exists key
        conn.set key, 'tried'
        raise StandardError
      end
    end
  end
end
