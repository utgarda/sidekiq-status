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
    require 'sidekiq/cli'
    Sidekiq.options[:queues] << 'default'
    Sidekiq::CLI.instance.run
  end
  yield
ensure
  Process.kill 'INT', pid
end