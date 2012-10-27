require 'spec_helper'

describe Sidekiq::Status::ClientMiddleware do

  let!(:redis) { Sidekiq.redis { |conn| conn } }
  let!(:job_id) { SecureRandom.hex(12) }

  # Clean Redis before each test
  before { redis.flushall }

  describe "#call" do
    it "sets queued status" do
      SecureRandom.should_receive(:hex).once.and_return(job_id)
      StubJob.perform_async(:arg1 => 'val1').should == job_id
      redis.hget(job_id, :status).should == 'queued'
    end

    it "sets status hash ttl" do
      SecureRandom.should_receive(:hex).once.and_return(job_id)
      StubJob.perform_async(:arg1 => 'val1').should == job_id
      (1..Sidekiq::Status::DEFAULT_EXPIRY).should cover redis.ttl(job_id)
    end

  end
end