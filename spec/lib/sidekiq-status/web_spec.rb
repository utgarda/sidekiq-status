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

  before do
    client_middleware
    allow(SecureRandom).to receive(:hex).and_return(job_id)
  end

  around { |example| start_server(&example) }

  it 'shows the list of jobs in progress' do
    capture_status_updates(2) do
      expect(LongJob.perform_async(1)).to eq(job_id)
    end

    get '/statuses'
    expect(last_response).to be_ok
    expect(last_response.body).to match(/#{job_id}/)
    expect(last_response.body).to match(/LongJob/)
    expect(last_response.body).to match(/working/)
  end

  it 'shows a single job in progress' do
    capture_status_updates(2) do
      LongJob.perform_async(1, 'another argument')
    end

    get "/statuses/#{job_id}"
    expect(last_response).to be_ok
    expect(last_response.body).to match(/#{job_id}/)
    expect(last_response.body).to match(/1,"another argument"/)
    expect(last_response.body).to match(/working/)
  end

  it 'show an error when the requested job ID is not found' do
    get '/statuses/12345'
    expect(last_response).to be_not_found
    expect(last_response.body).to match(/That job can't be found/)
  end
end
