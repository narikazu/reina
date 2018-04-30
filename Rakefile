#! /usr/bin/env ruby
require 'rake'

task default: %i(build install test)

task :build do
  sh 'gem build reina.gemspec'
end

task :install do
  sh 'gem install *.gem'
end

task :test do
  Dir['./specs/**/*_spec.rb'].each do |spec|
    sh "bundle exec rspec #{spec} --backtrace --color --format doc"
  end
end
