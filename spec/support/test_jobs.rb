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
      puts "job_messages_#{id}"
      conn.publish "job_messages_#{id}", "while in #perform, status = #{conn.hget id, :status}"
    end
  end
end
