require 'sidekiq-status'

class StubJob
  include Sidekiq::Worker
  include Sidekiq::Status::Worker

  sidekiq_options 'retry' => false

  def perform(*args)
  end
end

class ExpiryJob < StubJob
  def expiration
    15
  end
end

class LongJob < StubJob
  def perform(*args)
    sleep args[0] || 0.25
  end
end

class DataJob < StubJob
  def perform
    sleep 0.1
    store({data: 'meow'})
    retrieve(:data).should == 'meow'
    sleep 0.1
  end
end

class CustomDataJob < StubJob
  def perform
    store({mister_cat: 'meow'})
  end
end


class ProgressJob < StubJob
  def perform
    total 500
    at 100, 'howdy, partner?'
    sleep 0.1
  end
end

class ConfirmationJob < StubJob
  def perform(*args)
    Sidekiq.redis do |conn|
      conn.publish "job_messages_#{jid}", "while in #perform, status = #{conn.hget "sidekiq:status:#{jid}", :status}"
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

class RetryAndFailJob < StubJob
  sidekiq_options retry: 1

  def perform
    raise StandardError
  end
end

class FailingHardJob < StubJob
  def perform
    raise Exception
  end
end

class ExitedJob < StubJob
  def perform
    raise SystemExit
  end
end

class InterruptedJob < StubJob
  def perform
    raise Interrupt
  end
end

class RetriedJob < StubJob

  sidekiq_options 'retry' => true
  sidekiq_retry_in do |count| 3 end # 3 second delay > job timeout in test suite

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
