**Version 1.1.0**
+ Fixes the use case of multiple services sharing the same redis instance (#135)

**Version 1.0.2**
+ Fixes status not being set to `:failed` after retries

**Version 1.0.1**
+ Fixes namespacing in `sidekiq-status/testing/inline`

**Version 1.0.0**
+ Version number bumped to indicate stable release

**Version 0.8.1**
+ Avoids transient celluloid dependency in Sidekiq < 5.x

**Version 0.8.0**
+ Properly ignores jobs that do not have `Sidekiq::Status::Worker` included
+ Honors custom job expirations for ActiveJob jobs
+ Adds a `:retrying` status
+ Adds remove / retry buttons to the index page
+ Server middleware will now catches all exception types
+ Changes where server middleware is inserted in the chain
+ Reduces the amount of Redis calls made
+ Adds pagination / per page setting
+ Restores column sorting functionality

**Version 0.7.0**
+ Sidekiq 4.2 and 5 now supported
+ Added full support for ActiveJob
+ Updated Web UI
  + Styling updated to stay consistent with Sidekiq UI
  + Added header sorting
  + Fixed argument formatting
  + Times now display using natural language via ChronicDuration
+ Test suite fixed

**Version 0.6.0**
+ Updated Web UI
  + Will have all job statuses, previously it was showing only :working status
  + Bootstrap lables instead of badges for status
  + Added Arguments column to statuses page
+ New :interrupted status added
+ Added way to specify :expiration for Sidekiq::Status::ClientMiddleware
+ Bug fixes & Code cleaup

**Version 0.5.3**
+ some tweaks in web UI, separate redis namespace

**Version 0.5.2**
+ Sidekiq versions up to 3.3.* supported, jobs sorting options in web UI, more ruby versions

**Version 0.5.1**
+ dependencies versions requirements relaxed

**Version 0.5.0**
+ Sidekiq v3 support, redis pools support

**Version 0.4.0**
+ WebUI added, per-worker expiration setting enabled
