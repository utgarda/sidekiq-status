module Sidekiq::Status::AsCollection
  NAMESPACE = 'sidekiq:statuses_all'.freeze
  UPDATE_TIME = 'update_time'.freeze
  HASH_KEYS = [:update_time, :status, :args].freeze
  DEFAULT_ORDER = 'DESC'.freeze

  def self.included(base)
    super
    base.extend ClassMethods
  end

  def keys_collection
    self.class.keys_collection
  end

  module ClassMethods
    def all(page: 1, per_page: 10, order: DEFAULT_ORDER, by: UPDATE_TIME)
      Collection.new(to_s, page, per_page, order, by)
    end

    def refresh_collection
      base_collection.refresh_collection
    end

    def keys_collection
      base_collection.keys_collection
    end

    def total
      base_collection.total
    end

    private

    def base_collection
      @base_collection ||= Collection.new(to_s)
    end
  end

  class Collection
    include Enumerable

    # @param [String] worker_name
    # @param [Int] page optional requested page
    # @param [Int] per_page optional count of records
    # @param [String] order optional order direction ASC or DESC
    # @param [String] by optional field to order by
    def initialize(worker_name, page = 1, per_page = 10, order = DEFAULT_ORDER, by = UPDATE_TIME)
      @worker_name = worker_name
      @page = page
      @per_page = per_page
      @order = order
      @by = by
    end

    # Uses worker_name to pick redis set of jids and sort and get paginated results
    # returns lazy enumerable
    def each(&block)
      Sidekiq.redis do |conn|
        conn
          .sort(
            keys_collection,
            limit: [(@page - 1) * @per_page, @per_page],
            by: "*->#{@by}",
            order: @order,
            get: ['#'] + HASH_KEYS.map { |k| "*->#{k}" }
          )
          .lazy
          .map { |arr| hash_from(arr) }
          .each(&block)
      end
    end

    # Uses worker_name to update collection with worker related status jids
    def refresh_collection
      Sidekiq.redis do |conn|
        worker_keys = conn.keys('sidekiq:status:*').select do |k|
          conn.hget(k, 'worker') == @worker_name
        end
        conn.del(keys_collection)
        break 0 if worker_keys.empty?
        conn.sadd keys_collection, worker_keys
      end
    end

    # Uses worker_name to return number of jids stored in redis set
    def total
      Sidekiq.redis { |conn| conn.scard(keys_collection) }
    end

    # Uses downcased worked_name to generate name of collection to store jids
    def keys_collection
      "#{NAMESPACE}:#{@worker_name.downcase}"
    end

    private

    def hash_from(array)
      {
        jid: array[0].split(':').last,
        worker: @worker_name
      }.merge!(Hash[HASH_KEYS.zip(array[1..-1])])
    end
  end
end
