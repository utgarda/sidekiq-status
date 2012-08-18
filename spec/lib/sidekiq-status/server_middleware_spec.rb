require 'spec_helper'

describe Sidekiq::Status::ServerMiddleware do

  let!(:redis) { Sidekiq.redis { |conn| conn } }
  let!(:job_id) { SecureRandom.uuid }

  # Clean Redis before each test
  before { redis.flushall }

  def confirmations_thread(messages_limit, *channels)
    Thread.new {
      confirmations = []
      Sidekiq.redis do |conn|
        conn.subscribe *channels do |on|
          on.message do |ch, msg|
            confirmations << msg
            conn.unsubscribe if confirmations.length == messages_limit
          end
        end
      end
      confirmations
    }
  end

  describe "#call" do
    it "sets working/complete status" do
      thread = confirmations_thread 3, "status_updates", "job_messages_#{job_id}"
      SecureRandom.should_receive(:uuid).once.and_return(job_id)
      start_server do
        ConfirmationJob.perform_async(:arg1 => 'val1').should == job_id
        thread.value.should =~ [job_id,
                                "while in #perform, status = working",
                                job_id]
      end
      redis.hget(job_id, :status).should == 'complete'
    end

    it "sets status hash ttl" do
      SecureRandom.should_receive(:uuid).once.and_return(job_id)
      StubJob.perform_async(:arg1 => 'val1').should == job_id
      (1..Sidekiq::Status::DEFAULT_EXPIRY).should cover redis.ttl(job_id)
    end

  end
end