require 'spec_helper'

describe Sidekiq::Status do

  let!(:redis) { Sidekiq.redis { |conn| conn } }
  let!(:job_id) { SecureRandom.hex(12) }
  let!(:job_id_1) { SecureRandom.hex(12) }
  let!(:unused_id) { SecureRandom.hex(12) }
  let!(:plain_sidekiq_job_id) { SecureRandom.hex(12) }
  let!(:retried_job_id) { SecureRandom.hex(12) }

  # Clean Redis before each test
  # Seems like flushall has no effect on recently published messages,
  # so we should wait till they expire
  before { redis.flushall; sleep 0.1 }

  describe ".status, .working?, .complete?" do
    it "gets job status by id as symbol" do
      SecureRandom.should_receive(:hex).once.and_return(job_id)

      start_server do
        capture_status_updates(2) {
          LongJob.perform_async(1).should == job_id
        }.should == [job_id]*2
        Sidekiq::Status.status(job_id).should == :working
        Sidekiq::Status.working?(job_id).should be_true
        Sidekiq::Status::queued?(job_id).should be_false
        Sidekiq::Status::failed?(job_id ).should be_false
        Sidekiq::Status::complete?(job_id).should be_false
        Sidekiq::Status::stopped?(job_id).should be_false
      end
      Sidekiq::Status.status(job_id).should == :complete
      Sidekiq::Status.complete?(job_id).should be_true
    end
  end

  describe ".get" do
    it "gets a single value from data hash as string" do
      SecureRandom.should_receive(:hex).once.and_return(job_id)

      start_server do
        capture_status_updates(3) {
          DataJob.perform_async.should == job_id
        }.should == [job_id]*3
        Sidekiq::Status.get(job_id, :status).should == 'working'
      end
      Sidekiq::Status.get(job_id, :data).should == 'meow'
    end
  end

  describe ".num, .total, .pct_complete, .message" do
    it "should return job progress with correct type to it" do
      SecureRandom.should_receive(:hex).once.and_return(job_id)

      start_server do
        capture_status_updates(3) {
          ProgressJob.perform_async.should == job_id
        }.should == [job_id]*3
      end
      Sidekiq::Status.num(job_id).should == 100
      Sidekiq::Status.total(job_id).should == 500
      Sidekiq::Status.pct_complete(job_id).should == 20
      Sidekiq::Status.message(job_id).should == 'howdy, partner?'
    end
  end

  describe ".get_all" do
    it "gets the job hash by id" do
      SecureRandom.should_receive(:hex).once.and_return(job_id)

      start_server do
        capture_status_updates(2) {
          LongJob.perform_async(1).should == job_id
        }.should == [job_id]*2
        (hash = Sidekiq::Status.get_all(job_id)).should include 'status' => 'working'
        hash.should include 'update_time'
      end
      (hash = Sidekiq::Status.get_all(job_id)).should include 'status' => 'complete'
      hash.should include 'update_time'
    end
  end

  describe ".cancel" do
    it "cancels a job by id" do
      SecureRandom.should_receive(:hex).twice.and_return(job_id, job_id_1)
      start_server do
        job = LongJob.perform_in(3600)
        job.should == job_id
        second_job = LongJob.perform_in(3600)
        second_job.should == job_id_1

        initial_schedule = redis.zrange "schedule", 0, -1, {withscores: true}
        initial_schedule.size.should be 2
        initial_schedule.select {|scheduled_job| JSON.parse(scheduled_job[0])["jid"] == job_id }.size.should be 1

        Sidekiq::Status.unschedule(job_id).should be_true
        Sidekiq::Status.cancel(unused_id).should be_false # Unused, therefore unfound => false

        remaining_schedule = redis.zrange "schedule", 0, -1, {withscores: true}
        remaining_schedule.size.should == (initial_schedule.size - 1)
        remaining_schedule.select {|scheduled_job| JSON.parse(scheduled_job[0])["jid"] == job_id }.size.should be 0
      end
    end

    it "does not cancel a job with correct id but wrong time" do
      SecureRandom.should_receive(:hex).once.and_return(job_id)
      start_server do
        scheduled_time = Time.now.to_i + 3600
        returned_job_id = LongJob.perform_at(scheduled_time)
        returned_job_id.should == job_id

        initial_schedule = redis.zrange "schedule", 0, -1, {withscores: true}
        initial_schedule.size.should == 1
        Sidekiq::Status.cancel(returned_job_id, (scheduled_time + 1)).should be_false # wrong time, therefore unfound => false
        (redis.zrange "schedule", 0, -1, {withscores: true}).size.should be 1
        Sidekiq::Status.cancel(returned_job_id, (scheduled_time)).should be_true # same id, same time, deletes
        (redis.zrange "schedule", 0, -1, {withscores: true}).size.should be_zero
      end
    end
  end

  context "keeps normal Sidekiq functionality" do
    it "does jobs with and without included worker module" do
      SecureRandom.should_receive(:hex).exactly(4).times.and_return(plain_sidekiq_job_id, plain_sidekiq_job_id, job_id_1, job_id_1)
      start_server do
        capture_status_updates(12) {
          StubJob.perform_async.should == plain_sidekiq_job_id
          NoStatusConfirmationJob.perform_async(1)
          StubJob.perform_async.should == job_id_1
          NoStatusConfirmationJob.perform_async(2)
        }.should =~ [plain_sidekiq_job_id, job_id_1] * 6
      end
      redis.mget('NoStatusConfirmationJob_1', 'NoStatusConfirmationJob_2').should == %w(done)*2
      Sidekiq::Status.status(plain_sidekiq_job_id).should == :complete
      Sidekiq::Status.status(job_id_1).should == :complete
    end

    it "retries failed jobs" do
      SecureRandom.should_receive(:hex).once.and_return(retried_job_id)
      start_server do
        capture_status_updates(5) {
          RetriedJob.perform_async().should == retried_job_id
        }.should == [retried_job_id] * 5
      end
      Sidekiq::Status.status(retried_job_id).should == :complete
    end
  end

end
