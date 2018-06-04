# adapted from https://github.com/cryo28/sidekiq_status

module Sidekiq::Status
  # Hook into *Sidekiq::Web* Sinatra app which adds a new "/statuses" page
  module Web
    # Location of Sidekiq::Status::Web view templates
    VIEW_PATH = File.expand_path('../../../web/views', __FILE__)

    DEFAULT_PER_PAGE_OPTS = [25, 50, 100].freeze
    DEFAULT_PER_PAGE = 25
    COMMON_STATUS_HASH_KEYS = %w(update_time jid status worker args label pct_complete)

    class << self
      def per_page_opts= arr
        @per_page_opts = arr
      end
      def per_page_opts
        @per_page_opts || DEFAULT_PER_PAGE_OPTS
      end
      def default_per_page= val
        @default_per_page = val
      end
      def default_per_page
        @default_per_page || DEFAULT_PER_PAGE
      end
    end

    # @param [Sidekiq::Web] app
    def self.registered(app)

      # Allow method overrides to support RESTful deletes
      app.set :method_override, true

      app.helpers do
        def csrf_tag
          "<input type='hidden' name='authenticity_token' value='#{session[:csrf]}'/>"
        end

        def poll_path
          "?#{request.query_string}" if params[:poll]
        end

        def sidekiq_status_template(name)
          path = File.join(VIEW_PATH, name.to_s) + ".erb"
          File.open(path).read
        end

        def add_details_to_status(status)
          status['label'] = status_label(status['status'])
          status["pct_complete"] ||= pct_complete(status)
          status["web"] = process_custom_data(status)
          return status
        end

        def process_custom_data(hash)
          hash.reject { |key, _| COMMON_STATUS_HASH_KEYS.include?(key) }
        end

        def humanize_key(key)
          key.tr('_', ' ').capitalize
        end

        def pct_complete(status)
          return 100 if status['status'] == 'complete'
          Sidekiq::Status::pct_complete(status['jid']) || 0
        end

        def status_label(status)
          case status
          when 'complete'
            'success'
          when 'working', 'retrying'
            'warning'
          when 'queued'
            'primary'
          else
            'danger'
          end
        end

        def has_sort_by?(value)
          ["worker", "status", "update_time", "pct_complete", "message", "args"].include?(value)
        end
      end

      app.get '/statuses' do

        namespace_jids = Sidekiq.redis{ |conn| conn.keys('sidekiq:status:*') }
        jids = namespace_jids.map{ |id_namespace| id_namespace.split(':').last }
        @statuses = []

        jids.each do |jid|
          status = Sidekiq::Status::get_all jid
          next if !status || status.count < 2
          status = add_details_to_status(status)
          @statuses << status
        end

        sort_by = has_sort_by?(params[:sort_by]) ? params[:sort_by] : "update_time"
        sort_dir = "asc"

        if params[:sort_dir] == "asc"
          @statuses = @statuses.sort { |x,y| (x[sort_by] <=> y[sort_by]) || -1 }
        else
          sort_dir = "desc"
          @statuses = @statuses.sort { |y,x| (x[sort_by] <=> y[sort_by]) || 1 }
        end

        # Sidekiq pagination
        @total_size = @statuses.count
        @count = params[:per_page] ? params[:per_page].to_i : Sidekiq::Status::Web.default_per_page
        @count = @total_size if params[:per_page] == 'all'
        @current_page = params[:page].to_i < 1 ? 1 : params[:page].to_i
        @statuses = @statuses.slice((@current_page - 1) * @count, @count)

        @headers = [
          {id: "worker", name: "Worker / JID", class: nil, url: nil},
          {id: "args", name: "Arguments", class: nil, url: nil},
          {id: "status", name: "Status", class: nil, url: nil},
          {id: "update_time", name: "Last Updated", class: nil, url: nil},
          {id: "pct_complete", name: "Progress", class: nil, url: nil},
        ]

        @headers.each do |h|
          h[:url] = "statuses?" + params.merge("sort_by" => h[:id], "sort_dir" => (sort_by == h[:id] && sort_dir == "asc") ? "desc" : "asc").map{|k, v| "#{k}=#{CGI.escape v.to_s}"}.join("&")
          h[:class] = "sorted_#{sort_dir}" if sort_by == h[:id]
        end

        erb(sidekiq_status_template(:statuses))
      end

      app.get '/statuses/:jid' do
        job = Sidekiq::Status::get_all params['jid']

        if job.empty?
          halt [404, {"Content-Type" => "text/html"}, [erb(sidekiq_status_template(:status_not_found))]]
        else
          @status = add_details_to_status(job)
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
["per_page", "sort_by", "sort_dir"].each do |key|
  Sidekiq::WebHelpers::SAFE_QPARAMS.push(key)
end
if Sidekiq::Web.tabs.is_a?(Array)
  # For sidekiq < 2.5
  Sidekiq::Web.tabs << "statuses"
else
  Sidekiq::Web.tabs["Statuses"] = "statuses"
end
