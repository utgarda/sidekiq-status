require 'spec_helper'

describe Sidekiq::Status::AsCollection do
  let!(:redis) { Sidekiq.redis { |conn| conn } }
  let!(:job_id) { SecureRandom.hex(12) }
  let!(:job_id_1) { SecureRandom.hex(12) }
  let!(:unused_id) { SecureRandom.hex(12) }
  let!(:plain_sidekiq_job_id) { SecureRandom.hex(12) }
  let!(:retried_job_id) { SecureRandom.hex(12) }

  # Clean Redis before each test
  # Seems like flushall has no effect on recently published messages,
  # so we should wait till they expire
  before { redis.flushall; sleep 0.1; client_middleware }

  def all_keys(conn, worker)
    conn.smembers("#{Sidekiq::Status::AsCollection::NAMESPACE}:#{worker.to_s.downcase}") || 0
  end

  describe ".refresh_collection" do
    it "puts all keys under sidekiq:status:* to sidekiq:statuses_all:collectionjob" do
      start_server do
        redis.hmset 'sidekiq:status:foo', { worker: 'CollectionJob' }.to_a.flatten(1)
        redis.hmset 'sidekiq:status:foo1', { worker: 'CollectionJob' }.to_a.flatten(1)
        redis.hmset 'sidekiq:status:foo2', { worker: 'CollectionJob' }.to_a.flatten(1)
        redis.hmset 'sidekiq:status:foo3', { worker: 'WrongJob' }.to_a.flatten(1)

        expect(all_keys(redis, CollectionJob).size).to eq(0)
        expect(CollectionJob.refresh_collection).to eq(3)
        expect(all_keys(redis, CollectionJob).size).to eq(3)
        expect(all_keys(redis, CollectionJob).sort).to eq(['sidekiq:status:foo', 'sidekiq:status:foo1', 'sidekiq:status:foo2'])
      end
    end

    it 'does not put keys into collection if no matching' do
      start_server do
        redis.hmset 'sidekiq:status:foo3', { worker: 'WrongJob' }.to_a.flatten(1)

        expect(all_keys(redis, CollectionJob).size).to eq(0)
        expect(CollectionJob.refresh_collection).to eq(0)
        expect(all_keys(redis, CollectionJob).size).to eq(0)
        expect(all_keys(redis, CollectionJob).sort).to eq([])
      end
    end
  end

  describe '.total' do
    let(:jids) { 4.times.map { SecureRandom.hex(12) } }

    def seed_secure_random_with_job_ids
      allow(SecureRandom).to receive(:hex).exactly(4).times.and_return(*jids)
    end

    it 'returns count of stored keys for job' do
      seed_secure_random_with_job_ids
      start_server do
        capture_status_updates(12) { 4.times { CollectionJob.perform_async } }
      end
      expect(CollectionJob.total).to eq(4)
    end
  end

  describe '.all' do
    let(:jids) { 4.times.map { SecureRandom.hex(12) } }

    def seed_secure_random_with_job_ids
      allow(SecureRandom).to receive(:hex).exactly(4).times.and_return(*jids)
    end

    it 'picks sorted keys by update_time and allows to pick them by page' do
      seed_secure_random_with_job_ids
      start_server do
        capture_status_updates(12) { 4.times { CollectionJob.perform_async } }
      end
      expect(CollectionJob.all.to_a).to match_array(jids.map do |id|
        { update_time: anything, jid: id, status: 'complete', worker: 'CollectionJob', args: '' }
      end)
    end

    it 'does not touch redis if no iteration was requested' do
      seed_secure_random_with_job_ids
      start_server do
        capture_status_updates(12) { 4.times { CollectionJob.perform_async } }
      end
      expect(Sidekiq).not_to receive(:redis)
      expect(CollectionJob.all).to be_a(Sidekiq::Status::AsCollection::Collection)
    end
  end

  describe 'observing' do
    it 'adds job_id key to all key' do
      allow(SecureRandom).to receive(:hex).once.and_return(job_id)
      start_server do
        capture_status_updates(1) { CollectionJob.perform_async }
      end
      expect(all_keys(redis, CollectionJob)).to include("sidekiq:status:#{job_id}")
    end

    it 'deletes jid from collection' do
      allow(SecureRandom).to receive(:hex).once.and_return(job_id)
      start_server do
        capture_status_updates(2) { CollectionJob.perform_async(1) }
      end
      expect(all_keys(redis, CollectionJob).size).to eq(1)
      expect(Sidekiq::Status.delete(job_id, worker: CollectionJob)).to eq(1)
      expect(all_keys(redis, CollectionJob).size).to eq(0)
    end

    it 'canceles and deletes jid from collection' do
      start_server do
        allow(SecureRandom).to receive(:hex).once.and_return(job_id)
        expect(CollectionJob.perform_in(3600)).to eq(job_id)
        expect(all_keys(redis, CollectionJob).size).to eq(1)
        expect(Sidekiq::Status.unschedule(job_id, worker: CollectionJob)).to be_truthy
        expect(all_keys(redis, CollectionJob).size).to eq(0)
      end
    end
  end
end
