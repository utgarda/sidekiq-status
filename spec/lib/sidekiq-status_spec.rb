require 'spec_helper'

describe Sidekiq::Status do

  let!(:redis) { Sidekiq.redis { |conn| conn } }
  let!(:job_id) { SecureRandom.hex(12) }
  let!(:job_id_1) { SecureRandom.hex(12) }
  let!(:unused_id) { SecureRandom.hex(12) }
  let!(:plain_sidekiq_job_id) { SecureRandom.hex(12) }
  let!(:retried_job_id) { SecureRandom.hex(12) }
  let!(:retry_and_fail_job_id) { SecureRandom.hex(12) }

  describe ".status, .working?, .complete?" do
    it "gets job status by id as symbol" do
      allow(SecureRandom).to receive(:hex).once.and_return(job_id)

      start_server do
        expect(capture_status_updates(2) {
          expect(LongJob.perform_async(0.5)).to eq(job_id)
        }).to eq([job_id]*2)
        expect(Sidekiq::Status.status(job_id)).to eq(:working)
        expect(Sidekiq::Status.working?(job_id)).to be_truthy
        expect(Sidekiq::Status::queued?(job_id)).to be_falsey
        expect(Sidekiq::Status::retrying?(job_id)).to be_falsey
        expect(Sidekiq::Status::failed?(job_id)).to be_falsey
        expect(Sidekiq::Status::complete?(job_id)).to be_falsey
        expect(Sidekiq::Status::stopped?(job_id)).to be_falsey
        expect(Sidekiq::Status::interrupted?(job_id)).to be_falsey
      end
      expect(Sidekiq::Status.status(job_id)).to eq(:complete)
      expect(Sidekiq::Status.complete?(job_id)).to be_truthy
    end
  end

  describe ".get" do
    it "gets a single value from data hash as string" do
      allow(SecureRandom).to receive(:hex).once.and_return(job_id)

      start_server do
        expect(capture_status_updates(3) {
          expect(DataJob.perform_async).to eq(job_id)
        }).to eq([job_id]*3)
        expect(Sidekiq::Status.get(job_id, :status)).to eq('working')
      end
      expect(Sidekiq::Status.get(job_id, :data)).to eq('meow')
    end
  end

  describe ".at, .total, .pct_complete, .message" do
    it "should return job progress with correct type to it" do
      allow(SecureRandom).to receive(:hex).once.and_return(job_id)

      start_server do
        expect(capture_status_updates(4) {
          expect(ProgressJob.perform_async).to eq(job_id)
        }).to eq([job_id]*4)
      end
      expect(Sidekiq::Status.at(job_id)).to be(100)
      expect(Sidekiq::Status.total(job_id)).to be(500)
      # It returns a float therefor we need eq()
      expect(Sidekiq::Status.pct_complete(job_id)).to eq(20)
      expect(Sidekiq::Status.message(job_id)).to eq('howdy, partner?')
    end
  end

  describe ".get_all" do
    it "gets the job hash by id" do
      allow(SecureRandom).to receive(:hex).once.and_return(job_id)

      start_server do
        expect(capture_status_updates(2) {
          expect(LongJob.perform_async(0.5)).to eq(job_id)
        }).to eq([job_id]*2)
        expect(hash = Sidekiq::Status.get_all(job_id)).to include 'status' => 'working'
        expect(hash).to include 'update_time'
      end
      expect(hash = Sidekiq::Status.get_all(job_id)).to include 'status' => 'complete'
      expect(hash).to include 'update_time'
    end
  end

  describe '.delete' do
    it 'deletes the status hash for given job id' do
      allow(SecureRandom).to receive(:hex).once.and_return(job_id)
      start_server do
        expect(capture_status_updates(2) {
          expect(LongJob.perform_async(0.5)).to eq(job_id)
        }).to eq([job_id]*2)
      end
      expect(Sidekiq::Status.delete(job_id)).to eq(1)
    end

    it 'should not raise error while deleting status hash if invalid job id' do
      allow(SecureRandom).to receive(:hex).once.and_return(job_id)
      expect(Sidekiq::Status.delete(job_id)).to eq(0)
    end
  end

  describe ".cancel" do
    it "cancels a job by id" do
      allow(SecureRandom).to receive(:hex).twice.and_return(job_id, job_id_1)
      start_server do
        job = LongJob.perform_in(3600)
        expect(job).to eq(job_id)
        second_job = LongJob.perform_in(3600)
        expect(second_job).to eq(job_id_1)

        initial_schedule = redis.zrange "schedule", 0, -1, {withscores: true}
        expect(initial_schedule.size).to  be(2)
        expect(initial_schedule.select {|scheduled_job| JSON.parse(scheduled_job[0])["jid"] == job_id }.size).to be(1)

        expect(Sidekiq::Status.unschedule(job_id)).to be_truthy
        # Unused, therefore unfound => false
        expect(Sidekiq::Status.cancel(unused_id)).to be_falsey

        remaining_schedule = redis.zrange "schedule", 0, -1, {withscores: true}
        expect(remaining_schedule.size).to be(initial_schedule.size - 1)
        expect(remaining_schedule.select {|scheduled_job| JSON.parse(scheduled_job[0])["jid"] == job_id }.size).to be(0)
      end
    end

    it "does not cancel a job with correct id but wrong time" do
      allow(SecureRandom).to receive(:hex).once.and_return(job_id)
      start_server do
        scheduled_time = Time.now.to_i + 3600
        returned_job_id = LongJob.perform_at(scheduled_time)
        expect(returned_job_id).to eq(job_id)

        initial_schedule = redis.zrange "schedule", 0, -1, {withscores: true}
        expect(initial_schedule.size).to be(1)
        # wrong time, therefore unfound => false
        expect(Sidekiq::Status.cancel(returned_job_id, (scheduled_time + 1))).to be_falsey
        expect((redis.zrange "schedule", 0, -1, {withscores: true}).size).to be(1)
        # same id, same time, deletes
        expect(Sidekiq::Status.cancel(returned_job_id, (scheduled_time))).to be_truthy
        expect(redis.zrange "schedule", 0, -1, {withscores: true}).to be_empty
      end
    end
  end

  context "keeps normal Sidekiq functionality" do
    let(:expiration_param) { nil }

    it "does jobs with and without included worker module" do
      seed_secure_random_with_job_ids
      run_2_jobs!
      expect_2_jobs_are_done_and_status_eq :complete
      expect_2_jobs_ttl_covers 1..Sidekiq::Status::DEFAULT_EXPIRY
    end

    it "does jobs without a known class" do
      seed_secure_random_with_job_ids
      start_server(:expiration => expiration_param) do
        expect {
          Sidekiq::Client.new(Sidekiq.redis_pool).
            push("class" => "NotAKnownClass", "args" => [])
        }.to_not raise_error
      end
    end

    it "retries failed jobs" do
      allow(SecureRandom).to receive(:hex).and_return(retried_job_id)
      start_server do
        expect(capture_status_updates(3) {
          expect(RetriedJob.perform_async()).to eq(retried_job_id)
        }).to eq([retried_job_id] * 3)
        expect(Sidekiq::Status.status(retried_job_id)).to eq(:retrying)
        expect(Sidekiq::Status.working?(retried_job_id)).to be_falsey
        expect(Sidekiq::Status::queued?(retried_job_id)).to be_falsey
        expect(Sidekiq::Status::retrying?(retried_job_id)).to be_truthy
        expect(Sidekiq::Status::failed?(retried_job_id)).to be_falsey
        expect(Sidekiq::Status::complete?(retried_job_id)).to be_falsey
        expect(Sidekiq::Status::stopped?(retried_job_id)).to be_falsey
        expect(Sidekiq::Status::interrupted?(retried_job_id)).to be_falsey
      end
      expect(Sidekiq::Status.status(retried_job_id)).to eq(:retrying)
      expect(Sidekiq::Status::retrying?(retried_job_id)).to be_truthy

      # restarting and waiting for the job to complete
      start_server do
        expect(capture_status_updates(3) {}).to eq([retried_job_id] * 3)
        expect(Sidekiq::Status.status(retried_job_id)).to eq(:complete)
        expect(Sidekiq::Status.complete?(retried_job_id)).to be_truthy
        expect(Sidekiq::Status::retrying?(retried_job_id)).to be_falsey
      end
    end

    it "marks retried jobs as failed once they do eventually fail" do
      allow(SecureRandom).to receive(:hex).and_return(retry_and_fail_job_id)
      start_server do
        expect(
          capture_status_updates(3) {
            expect(RetryAndFailJob.perform_async).to eq(retry_and_fail_job_id)
          }
        ).to eq([retry_and_fail_job_id] * 3)

        expect(Sidekiq::Status.status(retry_and_fail_job_id)).to eq(:retrying)
      end

      # restarting and waiting for the job to fail
      start_server do
        expect(capture_status_updates(3) {}).to eq([retry_and_fail_job_id] * 3)

        expect(Sidekiq::Status.status(retry_and_fail_job_id)).to eq(:failed)
        expect(Sidekiq::Status.failed?(retry_and_fail_job_id)).to be_truthy
        expect(Sidekiq::Status::retrying?(retry_and_fail_job_id)).to be_falsey
      end
    end

    context ":expiration param" do
      before { seed_secure_random_with_job_ids }
      let(:expiration_param) { Sidekiq::Status::DEFAULT_EXPIRY * 100 }

      it "allow to overwrite :expiration parameter" do
        run_2_jobs!
        expect_2_jobs_are_done_and_status_eq :complete
        expect_2_jobs_ttl_covers (Sidekiq::Status::DEFAULT_EXPIRY+1)..expiration_param
      end

      it "allow to overwrite :expiration parameter by #expiration method from worker" do
        overwritten_expiration = expiration_param * 100
        allow_any_instance_of(NoStatusConfirmationJob).to receive(:expiration).
          and_return(overwritten_expiration)
        allow_any_instance_of(StubJob).to receive(:expiration).
          and_return(overwritten_expiration)
        run_2_jobs!
        expect_2_jobs_are_done_and_status_eq :complete
        expect_2_jobs_ttl_covers (expiration_param+1)..overwritten_expiration
      end

      it "reads #expiration from a method when defined" do
        allow(SecureRandom).to receive(:hex).once.and_return(job_id, job_id_1)
        start_server do
          expect(StubJob.perform_async).to eq(job_id)
          expect(ExpiryJob.perform_async).to eq(job_id_1)
          expect(redis.ttl("sidekiq:status:#{job_id}")).to eq(30 * 60)
          expect(redis.ttl("sidekiq:status:#{job_id_1}")).to eq(15)
        end
      end
    end

    def seed_secure_random_with_job_ids
      allow(SecureRandom).to receive(:hex).exactly(4).times.
        and_return(plain_sidekiq_job_id, plain_sidekiq_job_id, job_id_1, job_id_1)
    end

    def run_2_jobs!
      start_server(:expiration => expiration_param) do
        expect(capture_status_updates(6) {
          expect(StubJob.perform_async).to eq(plain_sidekiq_job_id)
          NoStatusConfirmationJob.perform_async(1)
          expect(StubJob.perform_async).to eq(job_id_1)
          NoStatusConfirmationJob.perform_async(2)
        }).to match_array([plain_sidekiq_job_id, job_id_1] * 3)
      end
    end

    def expect_2_jobs_ttl_covers(range)
      expect(range).to cover redis.ttl("sidekiq:status:#{plain_sidekiq_job_id}")
      expect(range).to cover redis.ttl("sidekiq:status:#{job_id_1}")
    end

    def expect_2_jobs_are_done_and_status_eq(status)
      expect(redis.mget('NoStatusConfirmationJob_1', 'NoStatusConfirmationJob_2')).to eq(%w(done)*2)
      expect(Sidekiq::Status.status(plain_sidekiq_job_id)).to eq(status)
      expect(Sidekiq::Status.status(job_id_1)).to eq(status)
    end
  end

end
