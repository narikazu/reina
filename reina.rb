require 'bundler'
Bundler.require

class NilClass; def blank?; true; end; end

CONFIG = {
  port:         ENV['PORT'],
  github_token: ENV['GITHUB_TOKEN'],
  platform_api: ENV['PLATFORM_API'],
  bot_name:     ENV.fetch('BOT_NAME', 'reina')
}.freeze

abort 'Please provide $PORT'         if CONFIG[:port].blank?
abort 'Please provide $GITHUB_TOKEN' if CONFIG[:github_token].blank?
abort 'Please provide $PLATFORM_API' if CONFIG[:platform_api].blank?

heroku = PlatformAPI.connect_oauth(CONFIG[:platform_api])

def on_pr_comment(payload, pr_number)
  return unless payload =~ /^\?d$/

  name = "staging-honeypot-pr-#{pr_number}"

  heroku = PlatformAPI.connect_oauth('e7dd6ad7-3c6a-411e-a2be-c9fe52ac7ed2')
  heroku.app.create(name: name)
  heroku.addon.create(name, { 'plan' => 'heroku-postgresql:dev' })
  heroku.addon.create(name, { 'plan' => 'heroku-redis:dev' })

  sh 'git clone https://github.com/honeypotio/honeypot'
  sh 'cd honeypot'
  sh "git remote add heroku git@heroku.com:#{name}.git"
  sh 'git push heroku master'

  add_comment_on_pr("Published on https://#{name}.herokuapp.com", pr_number)
end

def add_comment_on_pr(comment, pr_number)
  puts "##{pr_number}: #{comment}"
end

binding.pry
