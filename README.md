# Sidekiq::Status

[![Code Climate](https://codeclimate.com/github/utgarda/sidekiq-status.png)](https://codeclimate.com/github/utgarda/sidekiq-status)

An extension to [Sidekiq](http://github.com/mperham/sidekiq) message processing to track your jobs. Inspired
by [resque-status](http://github.com/quirkey/resque-status) and mostly copying its features, using Sidekiq's middleware.

## Installation

gem install sidekiq-status

## Usage

Configure your middleware chains, lookup [Middleware usage](https://github.com/mperham/sidekiq/wiki/Middleware)
on Sidekiq wiki for more info.

``` ruby
require 'sidekiq'
require 'sidekiq-status'

Sidekiq.configure_client do |config|
  config.client_middleware do |chain|
    chain.add Sidekiq::Status::ClientMiddleware
  end
end

Sidekiq.configure_server do |config|
  config.server_middleware do |chain|
    chain.add Sidekiq::Status::ServerMiddleware
  end
end
```

When defining those jobs you want to track later, include one more module. Jobs defined without Sidekiq::Status::Worker
will be processed as usual.

``` ruby
class MyJob
  include Sidekiq::Worker
  include Sidekiq::Status::Worker

  def perform(*args)
  # your code goes here
  end
end
```

Query for job status any time later:

``` ruby
job_id = MyJob.perform_async(*args)
# "queued", "working", "complete" or "failed" , nil after expiry (30 minutes)
status = Sidekiq::Status::get(job_id)
```

### Features coming
* Progress tracking, messages from running jobs
* Stopping jobs by id
* Minimal web UI

## License
MIT License , see LICENSE for more details.
© 2012 - 2013 Evgeniy Tsvigun
