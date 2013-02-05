require 'spec_helper'

describe Sidekiq::Status do

  let!(:redis) { Sidekiq.redis { |conn| conn } }
  let!(:job_id) { SecureRandom.hex(12) }
  let!(:job_id_1) { SecureRandom.hex(12) }

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
      end
      Sidekiq::Status.status(job_id).should == :complete
      Sidekiq::Status.complete?(job_id).should be_true
    end
  end

  describe ".get" do
    it "gets a single value from data hash as string" do
      SecureRandom.should_receive(:hex).once.and_return(job_id)

      start_server do
        capture_status_updates(2) {
          DataJob.perform_async.should == job_id
        }.should == [job_id]*2
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

  context "keeps normal Sidekiq functionality" do
    it "does jobs with and without included worker module" do
      SecureRandom.should_receive(:hex).exactly(4).times.and_return(job_id, job_id, job_id_1, job_id_1)
      start_server do
        capture_status_updates(12) {
          StubJob.perform_async.should == job_id
          NoStatusConfirmationJob.perform_async(1)
          StubJob.perform_async.should == job_id_1
          NoStatusConfirmationJob.perform_async(2)
        }.should =~ [job_id, job_id_1] * 6
      end
      redis.mget('NoStatusConfirmationJob_1', 'NoStatusConfirmationJob_2').should == %w(done)*2
      Sidekiq::Status.status(job_id).should == :complete
      Sidekiq::Status.status(job_id_1).should == :complete
    end

    it "retries failed jobs" do
      SecureRandom.should_receive(:hex).once.and_return(job_id)
      start_server do
        capture_status_updates(5) {
          RetriedJob.perform_async().should == job_id
        }.should == [job_id] * 5
      end
      Sidekiq::Status.status(job_id).should == :complete
    end
  end

end
