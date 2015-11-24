require 'spec_helper'

describe Sidekiq::Status::ClientMiddleware do

  let!(:redis) { Sidekiq.redis { |conn| conn } }
  let!(:job_id) { SecureRandom.hex(12) }
  let!(:active_job_id) { SecureRandom.hex(12) }
  let!(:args) { {'args' => [{'job_id' => active_job_id}]}}

  # Clean Redis before each test
  before { redis.flushall }

  describe "#call" do
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

    it "sets active job id mapped to sidekiq jid" do
      allow(SecureRandom).to receive(:hex).once.and_return(active_job_id)
      allow(SecureRandom).to receive(:hex).once.and_return(job_id)
      expect(StubJob.perform_async(:arg1 => 'val1')).to eq(job_id)
      Sidekiq::Status::ClientMiddleware.new.call(StubJob, {'jid' => job_id}.merge(args), :queued) do end
      expect(redis.hget("sidekiq:status:#{active_job_id}", 'jid')).to eq(job_id)
    end

    context "when redis_pool passed" do
      it "uses redis_pool" do
        redis_pool = double(:redis_pool)
        allow(redis_pool).to receive(:with)
        expect(Sidekiq).to_not receive(:redis)
        Sidekiq::Status::ClientMiddleware.new.call(StubJob, args.merge({'jid' => SecureRandom.hex}), :queued, redis_pool) do end
      end
    end

    context "when redis_pool is not passed" do
      it "uses Sidekiq.redis" do
        allow(Sidekiq).to receive(:redis)
        Sidekiq::Status::ClientMiddleware.new.call(StubJob, {'jid' => SecureRandom.hex}.merge(args), :queued) do end
      end
    end
  end
end
