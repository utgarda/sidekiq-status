# Sidekiq::Status
[![Gem Version](https://badge.fury.io/rb/sidekiq-status.svg)](http://badge.fury.io/rb/sidekiq-status)
[![Code Climate](https://codeclimate.com/github/utgarda/sidekiq-status.svg)](https://codeclimate.com/github/utgarda/sidekiq-status)
[![Build Status](https://secure.travis-ci.org/utgarda/sidekiq-status.svg)](http://travis-ci.org/utgarda/sidekiq-status)
[![Dependency Status](https://gemnasium.com/utgarda/sidekiq-status.svg)](https://gemnasium.com/utgarda/sidekiq-status)
[![Inline docs](http://inch-ci.org/github/utgarda/sidekiq-status.svg?branch=master)](http://inch-ci.org/github/utgarda/sidekiq-status)

An extension to [Sidekiq](http://github.com/mperham/sidekiq) message processing to track your jobs. Inspired
by [resque-status](http://github.com/quirkey/resque-status) and mostly copying its features, using Sidekiq's middleware.

Fully compatible with ActiveJob.

Supports the latest versions of Sidekiq and all the way back to 3.x.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'sidekiq-status'
```

And then execute:

```bash
$ bundle
```

Or install it yourself as:

```bash
gem install sidekiq-status
```

## Setup Checklist

To get started:

 * [Configure](#configuration) the middleware
 * (Optionally) add the [web interface](#adding-the-web-interface)
 * (Optionally) enable support for [ActiveJob](#activejob-support)

### Configuration

To use, add sidekiq-status to the middleware chains. See [Middleware usage](https://github.com/mperham/sidekiq/wiki/Middleware)
on the Sidekiq wiki for more info.

``` ruby
require 'sidekiq'
require 'sidekiq-status'

Sidekiq.configure_client do |config|
  # accepts :expiration (optional)
  Sidekiq::Status.configure_client_middleware config, expiration: 30.minutes
end

Sidekiq.configure_server do |config|
  # accepts :expiration (optional)
  Sidekiq::Status.configure_server_middleware config, expiration: 30.minutes

  # accepts :expiration (optional)
  Sidekiq::Status.configure_client_middleware config, expiration: 30.minutes
end
```

**Note:** This method of configuration is new as of version 0.8.0.

After that you can use your jobs as usual. You need to also include the `Sidekiq::Status::Worker` module in your jobs if you want the additional functionality of tracking progress and storing / retrieving job data.

``` ruby
class MyJob
  include Sidekiq::Worker
  include Sidekiq::Status::Worker # enables job status tracking

  def perform(*args)
  # your code goes here
  end
end
```

As of version 0.8.0, _only jobs that include `Sidekiq::Status::Worker`_ will have their statuses tracked. Previous versions of this gem used to track statuses for all jobs, even when `Sidekiq::Status::Worker` was not included.

To overwrite expiration on a per-worker basis, write an expiration method like the one below:

``` ruby
class MyJob
  include Sidekiq::Worker
  include Sidekiq::Status::Worker # enables job status tracking

  def expiration
    @expiration ||= 60 * 60 * 24 * 30 # 30 days
  end

  def perform(*args)
    # your code goes here
  end
end
```

The job status and any additional stored details will remain in Redis until the expiration time is reached. It is recommended that you find an expiration time that works best for your workload.

### Expiration Times

As sidekiq-status stores information about jobs in Redis, it is necessary to set an expiration time for the data that gets stored. A default expiration time may be configured at the time the middleware is loaded via the `:expiration` parameter.

As explained above, the default expiration may also be overridden on a per-job basis by defining it within the job itself via a method called `#expiration`.

The expiration time set will be used as the [Redis expire time](http://redis.io/commands/expire), which is also known as the TTL (time to live). Once the expiration time has passed, all information about the job's status and any custom data stored via sidekiq-status will disappear.

It is advised that you set the expiration time greater than the amount of time required to complete the job.

The default expiration time is 30 minutes.

### Retrieving Status

You may query for job status any time up to expiration:

``` ruby
job_id = MyJob.perform_async(*args)
# :queued, :working, :complete, :failed or :interrupted, nil after expiry (30 minutes)
status = Sidekiq::Status::status(job_id)
Sidekiq::Status::queued?      job_id
Sidekiq::Status::working?     job_id
Sidekiq::Status::retrying?    job_id
Sidekiq::Status::complete?    job_id
Sidekiq::Status::failed?      job_id
Sidekiq::Status::interrupted? job_id

```
Important: If you try any of the above status method after the expiration time, the result will be `nil` or `false`.

### ActiveJob Support

Version 0.7.0 has added full support for ActiveJob. The status of ActiveJob jobs will be tracked automatically.

To also enable job progress tracking and data storage features, simply add the  `Sidekiq::Status::Worker` module to your base class, like below:

```ruby
# app/jobs/application_job.rb
class ApplicationJob < ActiveJob::Base
  include Sidekiq::Status::Worker
end

# app/jobs/my_job.rb
class MyJob < ApplicationJob
  def perform(*args)
    # your code goes here
  end
end
```

### Tracking Progress and Storing Data

sidekiq-status comes with a feature that allows you to track the progress of a job, as well as store and retrieve any custom data related to a job.

``` ruby
class MyJob
  include Sidekiq::Worker
  include Sidekiq::Status::Worker # Important!

  def perform(*args)
    # your code goes here

    # the common idiom to track progress of your task
    total 100 # by default
    at 5, "Almost done" # 5/100 = 5 % completion

    # a way to associate data with your job
    store vino: 'veritas'

    # a way of retrieving stored data
    # remember that retrieved data is always String|nil
    vino = retrieve :vino
  end
end

job_id = MyJob.perform_async(*args)
data = Sidekiq::Status::get_all job_id
data # => {status: 'complete', update_time: 1360006573, vino: 'veritas'}
Sidekiq::Status::get     job_id, :vino #=> 'veritas'
Sidekiq::Status::at      job_id #=> 5
Sidekiq::Status::total   job_id #=> 100
Sidekiq::Status::message job_id #=> "Almost done"
Sidekiq::Status::pct_complete job_id #=> 5
```

### Unscheduling

```ruby
scheduled_job_id = MyJob.perform_in 3600
Sidekiq::Status.cancel scheduled_job_id #=> true
# doesn't cancel running jobs, this is more like unscheduling, therefore an alias:
Sidekiq::Status.unschedule scheduled_job_id #=> true

# returns false if invalid or wrong scheduled_job_id is provided
Sidekiq::Status.unschedule some_other_unschedule_job_id #=> false
Sidekiq::Status.unschedule nil #=> false
Sidekiq::Status.unschedule '' #=> false
# Note: cancel and unschedule are alias methods.
```
Important: If you schedule a job and then try any of the status methods after the expiration time, the result will be either `nil` or `false`. The job itself will still be in Sidekiq's scheduled queue and will execute normally. Once the job is started at its scheduled time, sidekiq-status' job metadata will once again be added back to Redis and you will be able to get status info for the job until the expiration time.

### Deleting Job Status by Job ID

Job status and metadata will automatically be removed from Redis once the expiration time is reached. But if you would like to remove job information from Redis prior to the TTL expiration, `Sidekiq::Status#delete` will do just that. Note that this will also remove any metadata that was stored with the job.

```ruby
# returns number of keys/jobs that were removed
Sidekiq::Status.delete(job_id) #=> 1
Sidekiq::Status.delete(bad_job_id) #=> 0
```

### Sidekiq Web Integration

This gem provides an extension to Sidekiq's web interface with an index at `/statuses`.

![Sidekiq Status Web](web/sidekiq-status-web.png)

As of 0.7.0, status information for an individual job may be found at `/statuses/:job_id`.

![Sidekiq Status Web](web/sidekiq-status-single-web.png)

As of 0.8.0, only jobs that include `Sidekiq::Status::Worker` will be reported in the web interface.

#### Adding the Web Interface

To use, setup the Sidekiq Web interface according to Sidekiq documentation and add the `Sidekiq::Status::Web` require:

``` ruby
require 'sidekiq/web'
require 'sidekiq-status/web'
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

## Contributing

Bug reports and pull requests are welcome. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](contributor-covenant.org) code of conduct.

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes along with test cases (`git commit -am 'Add some feature'`)
4. If possible squash your commits to one commit if they all belong to same feature.
5. Push to the branch (`git push origin my-new-feature`)
6. Create new Pull Request.

## Thanks
* Pramod Shinde
* Kenaniah Cerny
* Clay Allsopp
* Andrew Korzhuev
* Jon Moses
* Wayne Hoover
* Dylan Robinson
* Dmitry Novotochinov
* Mohammed Elalj
* Ben Sharpe

## License
MIT License, see LICENSE for more details.
© 2012 - 2016 Evgeniy Tsvigun
