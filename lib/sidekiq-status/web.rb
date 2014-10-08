# adapted from https://github.com/cryo28/sidekiq_status

module Sidekiq::Status
  # Hook into *Sidekiq::Web* Sinatra app which adds a new "/statuses" page
  module Web
    # Location of Sidekiq::Status::Web view templates
    VIEW_PATH = File.expand_path('../../../web/views', __FILE__)

    # @param [Sidekiq::Web] app
    def self.registered(app)
      app.helpers do
        def sidekiq_status_template(name)
          path = File.join(VIEW_PATH, name.to_s) + ".erb"
          File.open(path).read
        end
      end

      app.get '/statuses' do
        queue = Sidekiq::Workers.new
        @statuses = []

        queue.each do |*args|
          work = if args[1].is_a?(Hash)
            # For sidekiq < 3
            args[1]
          else
            args[2]
          end
          job = Struct.new(:jid, :klass, :args).new(work["payload"]["jid"], work["payload"]["class"], work["payload"]["args"])
          status = Sidekiq::Status::get_all job.jid
          next if !status || status.count < 2
          status["worker"] = job.klass
          status["args"] = job.args
          status["jid"] = job.jid
          status["pct_complete"] = ((status["at"].to_f / status["total"].to_f) * 100).to_i if status["total"].to_f > 0
          @statuses << OpenStruct.new(status)
        end

        erb(sidekiq_status_template(:statuses))
      end
    end
  end
end

require 'sidekiq/web' unless defined?(Sidekiq::Web)
Sidekiq::Web.register(Sidekiq::Status::Web)
if Sidekiq::Web.tabs.is_a?(Array)
  # For sidekiq < 2.5
  Sidekiq::Web.tabs << "statuses"
else
  Sidekiq::Web.tabs["Statuses"] = "statuses"
end
