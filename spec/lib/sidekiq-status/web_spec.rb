require 'spec_helper'
require 'sidekiq-status/web'
require 'rack/test'

describe 'sidekiq status web' do
  include Rack::Test::Methods

  let!(:redis) { Sidekiq.redis { |conn| conn } }
  let!(:job_id) { SecureRandom.hex(12) }

  # Clean Redis before each test
  # Seems like flushall has no effect on recently published messages,
  # so we should wait till they expire
  before { redis.flushall; sleep 0.1 }

  def app
    Sidekiq::Web
  end

  it 'shows a job in progress' do
    allow(SecureRandom).to receive(:hex).once.and_return(job_id)

    start_server do
      capture_status_updates(2) do
        expect(LongJob.perform_async(1)).to eq(job_id)
      end

      get '/statuses'
      expect(last_response.status).to eq(200)
      expect(last_response.body).to match(/#{job_id}/)
    end
  end

end
