require 'spec_helper'

describe Sidekiq::Status do

  let!(:redis) { Sidekiq.redis { |conn| conn } }
  let!(:job_id) { SecureRandom.uuid }

  # Clean Redis before each test
  # Seems like flushall has no effect on recently published messages,
  # so we should wait till they expire
  before { redis.flushall; sleep 0.1 }

  describe ".get" do
    it "gets job status by id" do
      SecureRandom.should_receive(:uuid).once.and_return(job_id)

      start_server do
        capture_status_updates(2) {
          LongJob.perform_async(1).should == job_id
        }.should == [job_id]*2
        Sidekiq::Status.get(job_id).should == "working"
      end
      Sidekiq::Status.get(job_id).should == 'complete'
    end
  end
end