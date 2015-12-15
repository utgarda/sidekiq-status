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

        def add_details_to_status(job, status)
          status["worker"] = job.klass
          status["args"] = job.args
          status["jid"] = job.jid
          status["pct_complete"] = Sidekiq::Status::pct_complete(job.jid)
          return status
        end

        def has_sort_by?(value)
          ["worker", "status", "update_time", "pct_complete", "message"].include?(value)
        end
      end

      app.get '/statuses' do
        queue = Sidekiq::Workers.new
        @statuses = []

        queue.each do |*args|
          # args[1].is_a?(Hash) is for sidekiq < 3
          work = args[1].is_a?(Hash) ? args[1] : args[2]
          payload = work["payload"] 
          job = Struct.new(:jid, :klass, :args).new(payload["jid"], payload["class"], payload["args"])
          status = Sidekiq::Status::get_all job.jid
          next if !status || status.count < 2
          status = add_details_to_status(job, status)
          @statuses << OpenStruct.new(status)
        end

        sort_by = has_sort_by?(params[:sort_by]) ? params[:sort_by] : "worker"
        sort_dir = "asc"

        if params[:sort_dir] == "asc"
          @statuses = @statuses.sort { |x,y| x.send(sort_by) <=> y.send(sort_by) }
        else
          sort_dir = "desc"
          @statuses = @statuses.sort { |y,x| x.send(sort_by) <=> y.send(sort_by) }
        end

        @headers = [
          { id: "worker", name: "Worker/jid", class: nil, url: nil},
          { id: "status", name: "Status", class: nil, url: nil},
          { id: "update_time", name: "Last Updated", class: nil, url: nil},
          { id: "pct_complete", name: "Progress", class: nil, url: nil},
          { id: "message", name: "Message", class: nil, url: nil}
        ]

        @headers.each do |h|
          params["sort_by"] = h[:id]
          params["sort_dir"] = (sort_by == h[:id] && sort_dir == "asc") ? "desc" : "asc"
          h[:url] = "statuses?" + params.map {|k,v| "#{k}=#{v}" }.join("&")
          h[:class] = "sorted_#{sort_dir}" if sort_by == h[:id]
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
