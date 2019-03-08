require "rspec"
require 'colorize'
require 'sidekiq'

# Celluloid should only be manually required before Sidekiq versions 4.+
require 'sidekiq/version'
require 'celluloid' if Gem::Version.new(Sidekiq::VERSION) < Gem::Version.new('4.0')

require 'sidekiq/processor'
require 'sidekiq/manager'
require 'sidekiq-status'

# Clears jobs before every test
RSpec.configure do |config|
  config.before(:each) do
    Sidekiq.redis { |conn| conn.flushall }
    client_middleware
    sleep 0.05
  end
end

Dir["#{File.dirname(__FILE__)}/support/**/*.rb"].each { |f| require f }

# Configures client middleware
def client_middleware client_middleware_options = {}
  Sidekiq.configure_client do |config|
    Sidekiq::Status.configure_client_middleware config, client_middleware_options
  end
end

def redis_thread messages_limit, *channels

  parent = Thread.current
  thread = Thread.new {
    messages = []
    Sidekiq.redis do |conn|
      puts "Subscribing to #{channels} for #{messages_limit.to_s.bold} messages".cyan if ENV['DEBUG']
      conn.subscribe_with_timeout 60, *channels do |on|
        on.subscribe do |ch, subscriptions|
          puts "Subscribed to #{ch}".cyan if ENV['DEBUG']
          if subscriptions == channels.size
            sleep 0.1 while parent.status != "sleep"
            parent.run
          end
        end
        on.message do |ch, msg|
          puts "Message received: #{ch} -> #{msg}".white if ENV['DEBUG']
          messages << msg
          conn.unsubscribe if messages.length >= messages_limit
        end
      end
    end
    puts "Returing from thread".cyan if ENV['DEBUG']
    messages
  }

  Thread.stop
  yield if block_given?
  thread

end

def capture_status_updates n, &block
  redis_thread(n, "status_updates", &block).value
end

# Configures server middleware and launches a sidekiq server
def start_server server_middleware_options = {}

  # Creates a process for the Sidekiq server
  pid = Process.fork do

    # Redirect the server's outputs
    $stdout.reopen File::NULL, 'w' unless ENV['DEBUG']
    $stderr.reopen File::NULL, 'w' unless ENV['DEBUG']

    # Load and configure server options
    require 'sidekiq/cli'
    Sidekiq.options[:queues] << 'default'
    Sidekiq.options[:require] = File.expand_path 'environment.rb', File.dirname(__FILE__)
    Sidekiq.options[:timeout] = 1
    Sidekiq.options[:concurrency] = 5

    # Add the server middleware
    Sidekiq.configure_server do |config|
      config.redis = Sidekiq::RedisConnection.create
      Sidekiq::Status.configure_server_middleware config, server_middleware_options
    end

    # Launch
    puts "Server starting".yellow if ENV['DEBUG']
    Sidekiq::CLI.instance.run

  end

  # Run the client-side code
  yield

  # Pause to ensure all jobs are picked up & started before TERM is sent
  sleep 0.2

  # Attempt to shut down the server normally
  Process.kill 'TERM', pid
  Process.wait pid

ensure

  # Ensure the server is actually dead
  Process.kill 'KILL', pid rescue "OK" # it's OK if the process is gone already

end
