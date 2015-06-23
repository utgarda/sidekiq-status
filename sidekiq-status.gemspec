# -*- encoding: utf-8 -*-
require File.expand_path('../lib/sidekiq-status/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ['Evgeniy Tsvigun']
  gem.email         = ['utgarda@gmail.com']
  gem.summary       = 'An extension to the sidekiq message processing to track your jobs'
  gem.homepage      = 'http://github.com/utgarda/sidekiq-status'
  gem.license       = 'MIT'

  gem.files         = `git ls-files`.split($\)
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = 'sidekiq-status'
  gem.require_paths = ['lib']
  gem.version       = Sidekiq::Status::VERSION

  gem.add_dependency                  'sidekiq', '>= 2.7'
  gem.add_development_dependency      'rack-test'
  gem.add_development_dependency      'rake'
  gem.add_development_dependency      'rspec'
  gem.add_development_dependency      'sinatra'
end
