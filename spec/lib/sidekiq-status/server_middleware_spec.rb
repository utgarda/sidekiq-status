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
      allow(SecureRandom).to receive(:hex).once.and_return(job_id)
      start_server do
        expect(ConfirmationJob.perform_async(:arg1 => 'val1')).to eq(job_id)
        expect(thread.value).to eq([job_id, job_id,
                                "while in #perform, status = working",
                                job_id])
      end
      expect(redis.hget("sidekiq:status:#{job_id}", :status)).to eq('complete')
      expect(Sidekiq::Status::complete?(job_id)).to be_truthy
    end

    it "sets failed status" do
      allow(SecureRandom).to receive(:hex).once.and_return(job_id)
      start_server do
        expect(capture_status_updates(3) {
          expect(FailingJob.perform_async).to eq(job_id)
        }).to eq([job_id]*3)
      end
      expect(redis.hget("sidekiq:status:#{job_id}", :status)).to eq('failed')
      expect(Sidekiq::Status::failed?(job_id)).to be_truthy
    end

    context "sets interrupted status" do 
      it "on system exit signal" do 
        allow(SecureRandom).to receive(:hex).once.and_return(job_id)
        start_server do
          expect(capture_status_updates(3) {
            expect(ExitedJob.perform_async).to eq(job_id)
          }).to eq([job_id]*3)
        end
        expect(redis.hget("sidekiq:status:#{job_id}", :status)).to eq('interrupted')
        expect(Sidekiq::Status::interrupted?(job_id)).to be_truthy
      end

      it "on interrupt signal" do 
        allow(SecureRandom).to receive(:hex).once.and_return(job_id)
        start_server do
          expect(capture_status_updates(3) {
            expect(InterruptedJob.perform_async).to eq(job_id)
          }).to eq([job_id]*3)
        end
        expect(redis.hget("sidekiq:status:#{job_id}", :status)).to eq('interrupted')
        expect(Sidekiq::Status::interrupted?(job_id)).to be_truthy
      end

    end

    it "sets status hash ttl" do
      allow(SecureRandom).to receive(:hex).once.and_return(job_id)
      start_server do
        expect(StubJob.perform_async(:arg1 => 'val1')).to eq(job_id)
      end
      expect(1..Sidekiq::Status::DEFAULT_EXPIRY).to cover redis.ttl("sidekiq:status:#{job_id}")
    end
  end

  describe ":expiration parameter" do
    let(:huge_expiration) { Sidekiq::Status::DEFAULT_EXPIRY * 100 }
    before do
      allow(SecureRandom).to receive(:hex).once.and_return(job_id)
    end

    it "overwrites default expiry value" do
      start_server(:expiration => huge_expiration) do
        StubJob.perform_async(:arg1 => 'val1')
      end
      expect((Sidekiq::Status::DEFAULT_EXPIRY+1)..huge_expiration).to cover redis.ttl("sidekiq:status:#{job_id}")
    end

    it "can be overwritten by worker expiration method" do
      overwritten_expiration = huge_expiration * 100
      allow_any_instance_of(StubJob).to receive(:expiration).and_return(overwritten_expiration)
      start_server(:expiration => huge_expiration) do
        StubJob.perform_async(:arg1 => 'val1')
      end
      expect((huge_expiration+1)..overwritten_expiration).to cover redis.ttl("sidekiq:status:#{job_id}")
    end
  end
end
