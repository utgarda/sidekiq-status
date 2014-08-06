# adapted from https://github.com/cryo28/sidekiq_status

module Sidekiq
  module Status
    # Hook into *Sidekiq::Web* Sinatra app which adds a new "/statuses" page
    module Web
      # Location of Sidekiq::Status::Web view templates
      VIEW_PATH = ::File.expand_path('../../../web/views', __FILE__)

      # @param [Sidekiq::Web] app
      class << self
        def init_helpers(app)
          app.helpers do
            def sidekiq_status_template(name)
              path = ::File.join(VIEW_PATH, name.to_s) + '.erb'
              ::File.open(path).read
            end

            def worker_info(status, job)
              status['worker'] = job.klass
              status['args']   = job.args
              status['jid']    = job.jid
              if status['total'].to_f > 0
                status['pct_complete'] = calculate_progress(status)
              end
              ::OpenStruct.new(status)
            end

            def calculate_progress(status)
              ((status['at'].to_f / status['total'].to_f) * 100).to_i
            end
          end
        end

        def init_route(app)
          app.get '/statuses' do
            queue     = ::Sidekiq::Workers.new
            @statuses = []

            queue.each do |_process, _name, work, _started_at|
              job    = ::Struct.new(:jid, :klass, :args).new(work['payload']['jid'],
                                                             work['payload']['class'],
                                                             work['payload']['args'])
              status = ::Sidekiq::Status.get_all(job.jid)
              next if !status || status.count < 2
              @statuses << worker_info(status, job)
            end

            erb(sidekiq_status_template(:statuses))
          end
        end

        def registered(app)
          init_helpers(app)
          init_route(app)
        end
      end
    end
  end
end

require 'sidekiq/web' unless defined?(Sidekiq::Web)
Sidekiq::Web.register(Sidekiq::Status::Web)
if Sidekiq::Web.tabs.is_a?(Array)
  # For sidekiq < 2.5
  Sidekiq::Web.tabs << 'statuses'
else
  Sidekiq::Web.tabs['Statuses'] = 'statuses'
end
