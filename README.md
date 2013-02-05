# Sidekiq::Status

[![Code Climate](https://codeclimate.com/github/utgarda/sidekiq-status.png)](https://codeclimate.com/github/utgarda/sidekiq-status)

An extension to [Sidekiq](http://github.com/mperham/sidekiq) message processing to track your jobs. Inspired
by [resque-status](http://github.com/quirkey/resque-status) and mostly copying its features, using Sidekiq's middleware.

## Installation

gem install sidekiq-status

## Usage

### Configuration

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
    chain.add Sidekiq::Status::ServerMiddleware, expiration: 30.minutes # default
  end
end
```

After that you can use your jobs as usual and only include `Sidekiq::Status::Worker` module if you want additional functionality of tracking progress and passing any data from job to client.

``` ruby
class MyJob
  include Sidekiq::Worker

  def perform(*args)
  # your code goes here
  end
end
```

### Retrieving status

Query for job status any time later:

``` ruby
job_id = MyJob.perform_async(*args)
# :queued, :working, :complete or :failed , nil after expiry (30 minutes)
status = Sidekiq::Status::status(job_id)
Sidekiq::Status::queued?   job_id
Sidekiq::Status::working?  job_id
Sidekiq::Status::complete? job_id
Sidekiq::Status::failed?   job_id
```

### Tracking progress, saving and retrieveing data associated with job

``` ruby
class MyJob
  include Sidekiq::Worker
  include Sidekiq::Status::Worker # Important!

  def perform(*args)
    # your code goes here

    # the common idiom to track progress of your task
    at 5, 100, "Almost done"

    # a way to associate data with your job
    store vino: 'veritas'

    # a way of retrieving said data
    vino = retrieve :vino
  end
end

job_id = MyJob.perform_async(*args)
data = Sidekiq::Status::get_all job_id
data # => {status: 'complete', update_time: 1360006573, vino: 'veritas'}
Sidekiq::Status::get     job_id, :vino #=> 'veritas'
Sidekiq::Status::num     job_id #=> 5
Sidekiq::Status::total   job_id #=> 100
Sidekiq::Status::message job_id #=> "Almost done"
Sidekiq::Status::pct_complete job_id #=> 5
```

### Features coming
* Stopping jobs by id
* Minimal web UI

## License
MIT License , see LICENSE for more details.
© 2012 - 2013 Evgeniy Tsvigun
