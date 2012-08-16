sidekiq-status
==============

an extension to the sidekiq message processing to track your jobs

# Sidekiq::Status

TODO: Write a gem description

## Installation

gem install sidekiq-status

## Usage

``` ruby
require 'sidekiq'
require 'sidekiq-status'

class MyJob
  include Sidekiq::Worker
  include Sidekiq::Status::Worker

  def perform(*args)
  # your code goes here
  end
end

job_id = MyJob.perform_async(*args)
Sidekiq::Status::get(job_id)
```

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
