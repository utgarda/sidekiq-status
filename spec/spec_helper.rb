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
    config.client_middleware do |chain|
      chain.add Sidekiq::Status::ClientMiddleware, client_middleware_options
    end
  end
end

def redis_thread messages_limit, *channels

  parent = Thread.current
  puts "Launching messages thread".cyan
  thread = Thread.new {
    puts "Running thread".cyan
    messages = []
    Sidekiq.redis do |conn|
      puts "Subscribing to #{channels} for #{messages_limit.to_s.bold} messages".cyan
      conn.subscribe_with_timeout 20, *channels do |on|
        on.subscribe do |ch, subscriptions|
          puts "Subscribed to #{ch}".cyan
          if subscriptions == channels.size
            sleep 0.1 while parent.status != "sleep"
            parent.run
          end
        end
        on.message do |ch, msg|
          puts "Message received: #{ch} -> #{msg}".white
          messages << msg
          conn.unsubscribe if messages.length >= messages_limit
        end
      end
    end
    puts "Returing from thread".cyan
    messages
  }

  puts "Delegating to redis thread".blue
  Thread.stop
  puts "Preparing to yield to client code".blue
  yield if block_given?
  puts "Returning the redis thread".blue
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
    #$stdout.reopen File::NULL, 'w'
    #$stderr.reopen File::NULL, 'w'

    # Load and configure server options
    require 'sidekiq/cli'
    Sidekiq.options[:queues] << 'default'
    Sidekiq.options[:require] = File.expand_path('environment.rb', File.dirname(__FILE__))
    Sidekiq.options[:timeout] = 1
    Sidekiq.options[:concurrency] = 5

    # Add the server middleware
    Sidekiq.configure_server do |config|
      config.redis = Sidekiq::RedisConnection.create
      config.server_middleware do |chain|
        chain.add Sidekiq::Status::ServerMiddleware, server_middleware_options
      end
    end

    # Launch
    Sidekiq::CLI.instance.run

  end

  # Ensures that the server will eventually be shut down at some point
  #Timeout::timeout 5 do

    puts "Server started".yellow
    # Run the client-side code now that server has been launched
    yield

    # Attempt to shut down the server normally
    puts "TERM #{pid}".yellow
    Process.kill 'TERM', pid
    puts "Waiting on #{pid}".yellow
    Process.wait pid

  #end rescue Timeout::Error

ensure

  # Ensure the server is actually dead
  puts "KILL #{pid}".yellow
  Process.kill 'KILL', pid rescue "OK" # it's OK if the process is gone already

end
