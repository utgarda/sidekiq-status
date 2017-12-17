# adapted from https://github.com/cryo28/sidekiq_status

module Sidekiq::Status
  # Hook into *Sidekiq::Web* Sinatra app which adds a new "/statuses" page
  module Web
    # Location of Sidekiq::Status::Web view templates
    VIEW_PATH = File.expand_path('../../../web/views', __FILE__)

    # @param [Sidekiq::Web] app
    def self.registered(app)

      # Allow method overrides to support RESTful deletes
      app.set :method_override, true

      app.helpers do
        def csrf_tag
          "<input type='hidden' name='authenticity_token' value='#{session[:csrf]}'/>"
        end

        def sidekiq_status_template(name)
          path = File.join(VIEW_PATH, name.to_s) + ".erb"
          File.open(path).read
        end

        def add_details_to_status(status)
          status['label'] = status_label(status['status'])
          status["pct_complete"] ||= pct_complete(status)
          return status
        end

        def pct_complete(status)
          return 100 if status['status'] == 'complete'
          Sidekiq::Status::pct_complete(status['jid']) || 0
        end

        def status_label(status)
          case status
          when 'complete'
            'success'
          when 'working'
            'warning'
          when 'queued'
            'primary'
          else
            'danger'
          end
        end

        def has_sort_by?(value)
          ["worker", "status", "update_time", "pct_complete", "message"].include?(value)
        end
      end

      app.get '/statuses' do
        namespace_jids = Sidekiq.redis{ |conn| conn.keys('sidekiq:status:*') }
        jids = namespace_jids.map{|id_namespace| id_namespace.split(':').last }
        @statuses = []

        jids.each do |jid|
          status = Sidekiq::Status::get_all jid
          next if !status || status.count < 2
          status = add_details_to_status(status)
          @statuses << OpenStruct.new(status)
        end

        sort_by = has_sort_by?(params[:sort_by]) ? params[:sort_by] : "update_time"
        sort_dir = "asc"

        if params[:sort_dir] == "asc"
          @statuses = @statuses.sort { |x,y| x.send(sort_by) <=> y.send(sort_by) }
        else
          sort_dir = "desc"
          @statuses = @statuses.sort { |y,x| x.send(sort_by) <=> y.send(sort_by) }
        end

        working_jobs = @statuses.select{|job| job.status == "working"}
        size = params[:size] ? params[:size].to_i : 25
        if working_jobs.size >= size
         @statuses = working_jobs
        else
         @statuses = (@statuses.size >= size) ? @statuses.take(size) : @statuses
        end


        @headers = [
          { id: "worker", name: "Worker / JID", class: nil, url: nil},
          { id: "args", name: "Arguments", class: nil, url: nil},
          { id: "status", name: "Status", class: nil, url: nil},
          { id: "update_time", name: "Last Updated", class: nil, url: nil},
          { id: "pct_complete", name: "Progress", class: nil, url: nil},
        ]

        @headers.each do |h|
          params["sort_by"] = h[:id]
          params["sort_dir"] = (sort_by == h[:id] && sort_dir == "asc") ? "desc" : "asc"
          h[:url] = "statuses?" + params.map {|k,v| "#{k}=#{v}" }.join("&")
          h[:class] = "sorted_#{sort_dir}" if sort_by == h[:id]
        end

        erb(sidekiq_status_template(:statuses))
      end

      app.get '/statuses/:jid' do
        job = Sidekiq::Status::get_all params['jid']

        if job.empty?
          halt [404, {"Content-Type" => "text/html"}, [erb(sidekiq_status_template(:status_not_found))]]
        else
          @status = OpenStruct.new(add_details_to_status(job))
          erb(sidekiq_status_template(:status))
        end
      end

      # Retries a failed job from the status list
      app.put '/statuses' do
        job = Sidekiq::RetrySet.new.find_job(params[:jid])
        job ||= Sidekiq::DeadSet.new.find_job(params[:jid])
        job.retry if job
        halt [302, { "Location" => request.referer }, []]
      end

      # Removes a completed job from the status list
      app.delete '/statuses' do
        Sidekiq::Status.delete(params[:jid])
        halt [302, { "Location" => request.referer }, []]
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
