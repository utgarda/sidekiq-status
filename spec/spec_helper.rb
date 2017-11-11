require "rspec"

require 'sidekiq'
require 'sidekiq/processor'
require 'sidekiq/manager'
require 'sidekiq-status'

# Clears jobs before every test
RSpec.configure do |config|
  config.before(:each) do
    Sidekiq.redis { |conn| conn.flushall }
    sleep 0.05
  end
end

Dir["#{File.dirname(__FILE__)}/support/**/*.rb"].each { |f| require f }

def client_middleware(client_middleware_options={})
  Sidekiq.configure_client do |config|
    config.client_middleware do |chain|
      chain.add Sidekiq::Status::ClientMiddleware, client_middleware_options
    end
  end
end

def confirmations_thread(messages_limit, *channels)
  parent = Thread.current
  thread = Thread.new {
    confirmations = []
    Sidekiq.redis do |conn|
      conn.subscribe *channels do |on|
        on.subscribe do |ch, subscriptions|
          if subscriptions == channels.size
            sleep 0.1 while parent.status != "sleep"
            parent.run
          end
        end
        on.message do |ch, msg|
          confirmations << msg
          conn.unsubscribe if confirmations.length >= messages_limit
        end
      end
    end
    confirmations
  }
  Thread.stop
  yield if block_given?
  thread
end

def capture_status_updates(n, &block)
  confirmations_thread(n, "status_updates", &block).value
end

def start_server(server_middleware_options={})
  pid = Process.fork do
    $stdout.reopen File::NULL, 'w'
    $stderr.reopen File::NULL, 'w'
    require 'sidekiq/cli'
    Sidekiq.options[:queues] << 'default'
    Sidekiq.options[:require] = File.expand_path('environment.rb', File.dirname(__FILE__))
    Sidekiq.options[:timeout] = 2
    Sidekiq.options[:concurrency] = 5
    Sidekiq.configure_server do |config|
      config.redis = Sidekiq::RedisConnection.create
      config.server_middleware do |chain|
        chain.add Sidekiq::Status::ServerMiddleware, server_middleware_options
      end
    end
    Sidekiq::CLI.instance.run
  end

  yield
  sleep 0.1
  Process.kill 'TERM', pid
  Timeout::timeout(5) { Process.wait pid } rescue Timeout::Error
ensure
  Process.kill 'KILL', pid rescue "OK" # it's OK if the process is gone already
end
