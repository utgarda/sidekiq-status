# Sidekiq::Status
[![Gem Version](https://badge.fury.io/rb/sidekiq-status.png)](http://badge.fury.io/rb/sidekiq-status)
[![Code Climate](https://codeclimate.com/github/utgarda/sidekiq-status.png)](https://codeclimate.com/github/utgarda/sidekiq-status)
[![Build Status](https://secure.travis-ci.org/utgarda/sidekiq-status.png)](http://travis-ci.org/utgarda/sidekiq-status)
[![Dependency Status](https://gemnasium.com/utgarda/sidekiq-status.svg)](https://gemnasium.com/utgarda/sidekiq-status)
[![Inline docs](http://inch-ci.org/github/utgarda/sidekiq-status.svg?branch=master)](http://inch-ci.org/github/utgarda/sidekiq-status)

An extension to [Sidekiq](http://github.com/mperham/sidekiq) message processing to track your jobs. Inspired
by [resque-status](http://github.com/quirkey/resque-status) and mostly copying its features, using Sidekiq's middleware.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'sidekiq-status'
```
And then execute:

    $ bundle

Or install it yourself as:

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
    # accepts :expiration (optional)
    chain.add Sidekiq::Status::ClientMiddleware, expiration: 30.minutes # default
  end
end

Sidekiq.configure_server do |config|
  config.server_middleware do |chain|
    # accepts :expiration (optional)
    chain.add Sidekiq::Status::ServerMiddleware, expiration: 30.minutes # default
  end
  config.client_middleware do |chain|
    # accepts :expiration (optional)
    chain.add Sidekiq::Status::ClientMiddleware, expiration: 30.minutes # default
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

### What is expiration time ?
As you noticed you can set expiration time for jobs globally by expiration option while adding middleware or writing a expiration method on each worker this expiration time is nothing but

+ [Redis expire time](http://redis.io/commands/expire), also know as TTL(time to live)
+ After expiration time all the info like status, update_time etc. about the worker disappears.
+ It is advised to set this expiration time greater than time required for completion of the job.
+ Default expiration time is 30 minutes.

### Retrieving status

Query for job status any time later:

``` ruby
job_id = MyJob.perform_async(*args)
# :queued, :working, :complete, :failed or :interrupted, nil after expiry (30 minutes)
status = Sidekiq::Status::status(job_id)
Sidekiq::Status::queued?      job_id
Sidekiq::Status::working?     job_id
Sidekiq::Status::complete?    job_id
Sidekiq::Status::failed?      job_id
Sidekiq::Status::interrupted? job_id

```
Important: If you try any of the above status method after the expiration time, will result into `nil` or `false`

### Tracking progress, saving, and retrieving data associated with job

``` ruby
class MyJob
  include Sidekiq::Worker
  include Sidekiq::Status::Worker # Important!

  def perform(*args)
    # your code goes here

    # the common idiom to track progress of your task
    total 100 # by default
    at 5, "Almost done"

    # a way to associate data with your job
    store vino: 'veritas'

    # a way of retrieving said data
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
Important: If you try any of the status method after the expiration time for scheduled jobs, will result into `nil` or `false`. But job will be in sidekiq's scheduled queue and will execute normally, once job is started on scheduled time you will get status info for job till expiration time defined on `Sidekiq::Status::ServerMiddleware`.

### Deleting Status by Job ID
```ruby
# returns number of keys/jobs that were removed
Sidekiq::Status.delete(job_id) #=> 1
Sidekiq::Status.delete(bad_job_id) #=> 0
```

### Sidekiq web integration

Sidekiq::Status also provides an extension to Sidekiq web interface with a `/statuses`.
![Sidekiq Status Web](https://raw.github.com/utgarda/sidekiq-status/master/web/sidekiq-status-web.png)

Setup Sidekiq web interface according to Sidekiq documentation and add the Sidekiq::Status::Web require:

``` ruby
require 'sidekiq/web'
require 'sidekiq-status/web'
```

### AsCollection

Sidekiq::Status::AsCollection provides interface to give sidekiq workers a collection methods.

```ruby
class MyJob
  include Sidekiq::Worker
  include Sidekiq::Status::AsCollection # Important!

  def perform(*args)
    # your code goes here
  end
end

job_id1 = MyJob.perform_async(*args)
job_id2 = MyJob.perform_async(*args)
job_id3 = MyJob.perform_async(*args)

MyJob.total #=> 3
MyJob.all.to_a #=> [
  { jid: job_id1, worker: 'MyJob', status: 'completed', args: '...' },
  { jid: job_id2, worker: 'MyJob', status: 'working', args: '...' },
  { jid: job_id3, worker: 'MyJob', status: 'queued', args: '...' }
]
```

#### Methods
The `Sidekiq::Status::AsCollection` module provides 3 next methods:

1. `::all(page:, per_page:, order:, by:)` - it used to pick the collection of status like in example above. You can pass custom `page`, `per_page`, `order` and `by`. By default it uses the following values: `page: 1, per_page: 10, order: 'DESC', by: 'update_time'`
2. `::total` - it used to get the total amount of keys in collection.
3. `::refresh_collection` - in case when you start using this feature after implementing worker just run the following code to update job related keys.

```ruby
MyJob.refresh_collection
```

**NOTE** if you are gonna to cancel and delete jobs manualy via `Sidekiq::Status.delete` and `Sidekiq::Status.cancel` pass worker class to keep collection updated.

```ruby
Sidekiq::Status.delete(jid, worker: MyJob)
Sidekiq::Status.cancel(jid, worker: MyJob)
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
* Clay Allsopp
* Andrew Korzhuev
* Jon Moses
* Wayne Hoover
* Dylan Robinson
* Dmitry Novotochinov
* Mohammed Elalj
* Ben Sharpe

## License
MIT License , see LICENSE for more details.
© 2012 - 2016 Evgeniy Tsvigun
