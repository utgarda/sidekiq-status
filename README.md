# Sidekiq::Status

[![Code Climate](https://codeclimate.com/github/utgarda/sidekiq-status.png)](https://codeclimate.com/github/utgarda/sidekiq-status)
[![Build Status](https://secure.travis-ci.org/utgarda/sidekiq-status.png)](http://travis-ci.org/utgarda/sidekiq-status)

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
  config.client_middleware do |chain|
    chain.add Sidekiq::Status::ClientMiddleware
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

To overwrite expiration on worker basis and don't use global expiration for all workers write a expiration method like this below:

``` ruby
class MyJob
  include Sidekiq::Worker

  def expiration
    @expiration ||= 60*60*24*30 # 30 days
  end

  def perform(*args)
    # your code goes here
  end
end
```

But keep in mind that such thing will store details of job as long as expiration is set, so it may charm your Redis storage/memory consumption. Because Redis stores all data in RAM.

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
    # remember that retrieved data is always is String|nil
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
### Unscheduling

```ruby
scheduled_job_id = MyJob.perform_in 3600
Sidekiq::Status.cancel scheduled_job_id #=> true
#doesn't cancel running jobs, this is more like unscheduling, therefore an alias:
Sidekiq::Status.unschedule scheduled_job_id #=> true
```

### Testing

Drawing analogy from [sidekiq testing by inlining](https://github.com/mperham/sidekiq/wiki/Testing#testing-workers-inline),
`sidekiq-status` allows to bypass redis and return a stubbed `:complete` status.
Since inlining your sidekiq worker will run it in-process, any exception it throws will make your test fail.
It will also run synchronously, so by the time you get to query the job status, the job will have been completed
successfully.
In other words, you'll get the `:complete` status only if the job didn't fail.

Inlining example:

You can run Sidekiq workers inline in your tests by requiring the `sidekiq/testing/inline` file in your `{test,spec}_helper.rb`:

`require 'sidekiq/testing/inline'`

To use `sidekiq-status` inlining, require it too in your `{test,spec}_helper.rb`:

`require 'sidekiq-status/testing/inline'`


### Features coming
* Stopping jobs by id

## Thanks
* Clay Allsopp
* Andrew Korzhuev
* Jon Moses
* Wayne Hoover
* Dylan Robinson

## License
MIT License , see LICENSE for more details.
© 2012 - 2014 Evgeniy Tsvigun
