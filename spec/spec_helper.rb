require "rspec"

require 'sidekiq'
require 'sidekiq-status'


Dir["#{File.dirname(__FILE__)}/support/**/*.rb"].each { |f| require f }

Sidekiq.configure_client do |config|
  config.client_middleware do |chain|
    chain.add Sidekiq::Status::ClientMiddleware
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

def start_server()
  pid = Process.fork do
    $stdout.reopen File::NULL, 'w'
    $stderr.reopen File::NULL, 'w'
    require 'sidekiq/cli'
    Sidekiq.options[:queues] << 'default'
    Sidekiq.configure_server do |config|
      config.server_middleware do |chain|
        config.redis = {:url => 'redis://localhost:6379'}
        chain.add Sidekiq::Status::ServerMiddleware
      end
    end
    Sidekiq::CLI.instance.run
  end

  yield

  sleep 0.1
  Process.kill 'TERM', pid
  Timeout::timeout(10) { Process.wait pid } rescue Timeout::Error
ensure
  Process.kill 'KILL', pid rescue "OK" # it's OK if the process is gone already
end