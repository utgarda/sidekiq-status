require 'spec_helper'

describe Sidekiq::Status::Worker do

  let!(:job_id) { SecureRandom.uuid }

  describe ".perform_async" do
    it "should do something" do
      SecureRandom.should_receive(:uuid).once.and_return(job_id)
      StubJob.perform_async().should == job_id
    end
  end
end