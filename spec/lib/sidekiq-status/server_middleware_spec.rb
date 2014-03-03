require 'spec_helper'

describe Sidekiq::Status::ServerMiddleware do

  let!(:redis) { Sidekiq.redis { |conn| conn } }
  let!(:job_id) { SecureRandom.hex(12) }

  # Clean Redis before each test
  # Seems like flushall has no effect on recently published messages,
  # so we should wait till they expire
  before { redis.flushall; sleep 0.1 }

  describe "#call" do
    it "sets working/complete status" do
      thread = confirmations_thread 4, "status_updates", "job_messages_#{job_id}"
      SecureRandom.should_receive(:hex).once.and_return(job_id)
      start_server do
        ConfirmationJob.perform_async(:arg1 => 'val1').should == job_id
        thread.value.should == [job_id, job_id,
                                "while in #perform, status = working",
                                job_id]
      end
      redis.hget(job_id, :status).should == 'complete'
      Sidekiq::Status::complete?(job_id).should be_true
    end

    it "sets failed status" do
      SecureRandom.should_receive(:hex).once.and_return(job_id)
      start_server do
        capture_status_updates(3) {
          FailingJob.perform_async.should == job_id
        }.should == [job_id]*3
      end
      redis.hget(job_id, :status).should == 'failed'
      Sidekiq::Status::failed?(job_id).should be_true
    end

    it "sets status hash ttl" do
      SecureRandom.should_receive(:hex).once.and_return(job_id)
      StubJob.perform_async(:arg1 => 'val1').should == job_id
      (1..Sidekiq::Status::DEFAULT_EXPIRY).should cover redis.ttl(job_id)
    end
  end

  describe ":expiration parameter" do
    let(:huge_expiration) { Sidekiq::Status::DEFAULT_EXPIRY * 100 }
    before do
      SecureRandom.should_receive(:hex).once.and_return(job_id)
    end
    it "overwrites default expiry value" do
      start_server(:expiration => huge_expiration) do
        StubJob.perform_async(:arg1 => 'val1')
      end
      ((Sidekiq::Status::DEFAULT_EXPIRY+1)..huge_expiration).should cover redis.ttl(job_id)
    end

    it "can be overwritten by worker expiration method" do
      overwritten_expiration = huge_expiration * 100
      StubJob.any_instance.stub(expiration: overwritten_expiration)
      start_server(:expiration => huge_expiration) do
        StubJob.perform_async(:arg1 => 'val1')
      end
      ((huge_expiration+1)..overwritten_expiration).should cover redis.ttl(job_id)
    end
  end
end
