require 'spec_helper'

describe Sidekiq::Status do
  let!(:job_id) { SecureRandom.hex(12) }
  describe '.status' do
    it 'bypasses redis with inlining enabled' do
      Process.fork {
        require 'sidekiq-status/testing/inline'
        expect(Sidekiq::Status.status(job_id)).to eq :complete
      }
    end
  end
end
