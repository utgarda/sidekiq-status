require 'spec_helper'

describe Sidekiq::Status::ClientMiddleware do

  let!(:redis) { Sidekiq.redis { |conn| conn } }
  let!(:job_id) { SecureRandom.hex(12) }

  # Clean Redis before each test
  before { redis.flushall }

  describe "#call" do
    before { client_middleware }
    it "sets queued status" do
      allow(SecureRandom).to receive(:hex).once.and_return(job_id)
      expect(StubJob.perform_async(:arg1 => 'val1')).to eq(job_id)
      expect(redis.hget("sidekiq:status:#{job_id}", :status)).to eq('queued')
      expect(Sidekiq::Status::queued?(job_id)).to be_truthy
    end

    it "sets status hash ttl" do
      allow(SecureRandom).to receive(:hex).once.and_return(job_id)
      expect(StubJob.perform_async(:arg1 => 'val1')).to eq(job_id)
      expect(1..Sidekiq::Status::DEFAULT_EXPIRY).to cover redis.ttl("sidekiq:status:#{job_id}")
    end

    context "when redis_pool passed" do
      it "uses redis_pool" do
        redis_pool = double(:redis_pool)
        allow(redis_pool).to receive(:with)
        expect(Sidekiq).to_not receive(:redis)
        Sidekiq::Status::ClientMiddleware.new.call(StubJob, {'jid' => SecureRandom.hex}, :queued, redis_pool) do end
      end
    end

    context "when redis_pool is not passed" do
      it "uses Sidekiq.redis" do
        allow(Sidekiq).to receive(:redis)
        Sidekiq::Status::ClientMiddleware.new.call(StubJob, {'jid' => SecureRandom.hex}, :queued) do end
      end
    end
  end

  describe ":expiration parameter" do
    let(:huge_expiration) { Sidekiq::Status::DEFAULT_EXPIRY * 100 }
    before do
      allow(SecureRandom).to receive(:hex).once.and_return(job_id)
    end

    it "overwrites default expiry value" do
      client_middleware(expiration: huge_expiration)
      StubJob.perform_async(:arg1 => 'val1')
      expect((Sidekiq::Status::DEFAULT_EXPIRY+1)..huge_expiration).to cover redis.ttl("sidekiq:status:#{job_id}")
    end
  end

  describe ":all_jobs parameter" do
    let!(:ordinary_job_id) { SecureRandom.hex(12) }
    let!(:status_job_id) { SecureRandom.hex(12) }

    it "should accept all jobs as true and track status for all jobs" do
      client_middleware(all_jobs: true)
      allow(SecureRandom).to receive(:hex).and_return(ordinary_job_id, status_job_id)

      expect(OrdinaryJob.perform_async(:arg1 => 'val1')).to eq(ordinary_job_id)
      expect(redis.hget("sidekiq:status:#{ordinary_job_id}", :status)).to eq('queued')
      expect(Sidekiq::Status::queued?(ordinary_job_id)).to be_truthy

      expect(StubJob.perform_async(:arg1 => 'val1')).to eq(status_job_id)
      expect(redis.hget("sidekiq:status:#{status_job_id}", :status)).to eq('queued')
      expect(Sidekiq::Status::queued?(status_job_id)).to be_truthy
    end

    it "should accept all jobs as false and only track status of Sidekiq::Status::Worker" do
      client_middleware(all_jobs: false)
      allow(SecureRandom).to receive(:hex).and_return(ordinary_job_id, status_job_id)

      expect(OrdinaryJob.perform_async(:arg1 => 'val1')).to eq(ordinary_job_id)
      expect(redis.hget("sidekiq:status:#{ordinary_job_id}", :status)).to be_nil
      expect(Sidekiq::Status::queued?(ordinary_job_id)).to be_falsey

      expect(StubJob.perform_async(:arg1 => 'val1')).to eq(status_job_id)
      expect(redis.hget("sidekiq:status:#{status_job_id}", :status)).to eq('queued')
      expect(Sidekiq::Status::queued?(status_job_id)).to be_truthy
    end
  end
end
