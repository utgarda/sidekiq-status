Version 0.6.0
+ Updated Web UI 
  + Will have all job statuses, previously it was showing only :working status
  + Bootstrap lables instead of badges for status 
  + Added Arguments column to statuses page 
+ New :interrupted status added 
+ Added way to specify :expiration for Sidekiq::Status::ClientMiddleware
+ Bug fixes & Code cleaup 

Version 0.5.3 
+ some tweaks in web UI, separate redis namespace

Version 0.5.2 
+ Sidekiq versions up to 3.3.* supported, jobs sorting options in web UI, more ruby versions

Version 0.5.1
+ dependencies versions requirements relaxed

Version 0.5.0
+ Sidekiq v3 support, redis pools support

Version 0.4.0
+ WebUI added, per-worker expiration setting enabled