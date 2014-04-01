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
      Sidekiq::Status::queued?(job_id).should be_true
    end

    it "sets status hash ttl" do
      SecureRandom.should_receive(:hex).once.and_return(job_id)
      StubJob.perform_async(:arg1 => 'val1').should == job_id
      (1..Sidekiq::Status::DEFAULT_EXPIRY).should cover redis.ttl(job_id)
    end

    context "when redis_pool passed" do
      it "uses redis_pool" do
        redis_pool = double(:redis_pool)
        redis_pool.should_receive(:with)
        Sidekiq.should_not_receive(:redis)
        Sidekiq::Status::ClientMiddleware.new.call(StubJob, {'jid' => SecureRandom.hex}, :queued, redis_pool) do end
      end
    end

    context "when redis_pool is not passed" do
      it "uses Sidekiq.redis" do
        Sidekiq.should_receive(:redis)
        Sidekiq::Status::ClientMiddleware.new.call(StubJob, {'jid' => SecureRandom.hex}, :queued) do end
      end
    end
  end
end
