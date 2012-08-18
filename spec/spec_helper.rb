require "rspec"

require 'sidekiq'
require 'sidekiq-status'


Dir["#{File.dirname(__FILE__)}/support/**/*.rb"].each { |f| require f }

Sidekiq.configure_client do |config|
  config.client_middleware do |chain|
    chain.add Sidekiq::Status::ClientMiddleware
  end
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
  Timeout::timeout(10) { Process.wait pid }
rescue Timeout::Error
  Process.kill 'KILL', pid rescue "OK" # it's OK if the process is gone already
end