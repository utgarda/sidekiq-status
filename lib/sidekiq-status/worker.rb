require "active_support"

module Sidekiq::Status::Worker
  extend ActiveSupport::Concern

  # Adding ID generation to .perform_async
  module ClassMethods
    # :nodoc:
    def self.extended(base)
      class << base
        alias_method_chain :perform_async, :uuid
      end
    end

    # Add an id to job arguments
    def perform_async_with_uuid(*args)
      id = SecureRandom.uuid
      args.unshift id
      perform_async_without_uuid(*args)
      id
    end
  end

  attr_reader :id

end