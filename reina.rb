require 'bundler'
require 'readline'
Bundler.require

require './config.rb'

if ENV['CONFIG'].present?
  self.class.send(:remove_const, 'CONFIG')

  CONFIG = ActiveSupport::HashWithIndifferentAccess.new(
    JSON.parse(ENV['CONFIG'])
  )
end

if ENV['APPS'].present?
  self.class.send(:remove_const, 'APPS')

  APPS = ActiveSupport::HashWithIndifferentAccess.new(
    JSON.parse(ENV['APPS'])
  )
end

class App
  DEFAULT_REGION = 'eu'.freeze
  DEFAULT_STAGE  = 'staging'.freeze
  DEFAULT_APP_NAME_PREFIX = CONFIG[:app_name_prefix].freeze

  attr_reader :heroku, :name, :project, :pr_number, :branch, :g

  def initialize(heroku, name, project, pr_number, branch)
    @heroku    = heroku
    @name      = name.to_s
    @project   = project
    @pr_number = pr_number
    @branch    = branch
  end

  def fetch_repository
    if Dir.exists?(name)
      @g = Git.open(name)
    else
      @g = Git.clone(github_url, name)
    end

    g.pull('origin', branch)
    g.checkout(g.branch(branch))

    unless g.remotes.map(&:name).include?(remote_name)
      g.add_remote(remote_name, remote_url)
    end
  end

  def create_app
    heroku.app.create(
      'name'   => app_name,
      'region' => project.fetch(:region, DEFAULT_REGION)
    )
  end

  def install_addons
    addons = project.fetch(:addons, []) + app_json.fetch('addons', [])
    addons.each do |addon|
      if addon.is_a?(Hash) && addon.has_key?('options')
        addon['config'] = addon.extract!('options')
      else
        addon = { 'plan' => addon }
      end

      heroku.addon.create(app_name, addon)
    end
  end

  def add_buildpacks
    buildpacks = project.fetch(:buildpacks, []).map do |buildpack|
      { 'buildpack' => buildpack }
    end + app_json.fetch('buildpacks', []).map do |buildpack|
      { 'buildpack' => buildpack['url'] }
    end

    heroku.buildpack_installation.update(app_name, 'updates' => buildpacks.uniq)
  end

  def set_env_vars
    config_vars = project.fetch(:config_vars, {})
    except = config_vars[:except]

    if config_vars.has_key?(:from)
      copy = config_vars.fetch(:copy, [])
      config_vars = heroku.config_var.info_for_app(config_vars[:from])

      vars_cache = {}
      copy.each do |h|
        unless h[:from].include?('#')
          s = config_vars[h[:from]]
          s << h[:append] if h[:append].present?
          config_vars[h[:to]] = s
          next
        end

        source, var = h[:from].split('#')
        source_app_name = app_name_for(source)
        if var == 'url'
          config_vars[h[:to]] = "https://#{domain_name_for(source_app_name)}"
        else
          vars_cache[source_app_name] ||= heroku.config_var.info_for_app(source_app_name)
          config_vars[h[:to]] = vars_cache[source_app_name][var]
        end
      end
    end

    config_vars.except!(*except) if except.present?

    config_vars['APP_NAME']        = app_name
    config_vars['HEROKU_APP_NAME'] = app_name
    config_vars['DOMAIN_NAME']     = domain_name

    app_json.fetch('env', {}).each do |key, hash|
      config_vars[key] = hash['value'] if hash['value'].present?
    end

    heroku.config_var.update(app_name, config_vars)
  end

  def setup_dynos
    formation = app_json.fetch('formation', {})
    return if formation.blank?

    formation.each do |k, h|
      h['size'] = 'free'

      heroku.formation.update(app_name, k, h)
    end
  end

  def add_to_pipeline
    return if project[:pipeline].blank?

    pipeline_id = heroku.pipeline.info(project[:pipeline])['id']
    heroku.pipeline_coupling.create(
      'app'      => app_name,
      'pipeline' => pipeline_id,
      'stage'    => DEFAULT_STAGE
    )
  end

  def execute_postdeploy_scripts
    script = app_json.dig('scripts', 'postdeploy')
    return if script.blank?

    `heroku run #{script} --app #{app_name}`
  end

  def deploy
    g.push(remote_name, 'master')
  end

  def app_json
    return @app_json if @app_json

    f = File.join(name, 'app.json')
    return {} unless File.exists?(f)

    @app_json = JSON.parse(File.read(f))
  end

  def domain_name
    domain_name_for(app_name)
  end

  def app_name
    app_name_for(name)
  end

  def remote_name
    "heroku-#{app_name}"
  end

  def parallel?
    project[:parallel] != false
  end

  private

  def domain_name_for(s)
    "#{s}.herokuapp.com"
  end

  def app_name_for(s)
    "#{DEFAULT_APP_NAME_PREFIX}#{s}-#{pr_number}"
  end

  def github_url
    "#{ENV.fetch('GITHUB_AUTH', 'git')}@github.com:#{project[:github]}"
  end

  def remote_url
    "https://git.heroku.com/#{app_name}.git"
  end
end

def main
  if ENV['GITHUB_AUTH'].present?
    `git config --global user.name "#{ENV['GITHUB_NAME']}"`
    `git config --global user.email "#{ENV['GITHUB_EMAIL']}"`

    unless File.exists?('.netrc')
      File.write('.netrc', "machine git.heroku.com login #{ENV['GITHUB_EMAIL']} password #{ENV['HEROKU_AUTH_TOKEN']}")
    end
  end

  heroku = PlatformAPI.connect_oauth(CONFIG[:platform_api])
  abort 'Please provide $PLATFORM_API' if CONFIG[:platform_api].blank?

  params = ARGV.dup
  pr_number = params.shift.to_i
  branches  = params.map { |param| param.split('#', 2) }.to_h
  abort 'Given PR number should be greater than 0' if pr_number <= 0

  apps = APPS.map do |name, project|
    branch = branches[name.to_s].presence || 'master'
    App.new(heroku, name, project, pr_number, branch)
  end

  apps.each do |app|
    abort "#{app.app_name} is too long pls send help" if app.app_name.length >= 30
  end

  existing_apps = heroku.app.list.map { |a| a['name'] } & apps.map(&:app_name)
  if ENV['DYNO'].present?
    existing_apps.each do |app|
      puts "Deleting #{app}"
      heroku.app.delete(app)
    end
  elsif existing_apps.present?
    puts 'The following apps already exist on Heroku:'
    puts existing_apps.map { |a| "- #{a}" }
    abort if Readline.readline('Type "OK" to delete the apps above: ', true).strip != 'OK'
    existing_apps.each do |app|
      puts "Deleting #{app}"
      heroku.app.delete(app)
    end
  end

  process_app = ->(app) do
    puts "#{app.name}: Fetching from #{app.project[:github]}..."
    app.fetch_repository

    puts "#{app.name}: Provisioning #{app.app_name} on Heroku..."
    app.create_app
    app.install_addons
    app.add_buildpacks
    app.set_env_vars

    puts "#{app.name}: Deploying to https://#{app.domain_name}..."
    app.deploy

    puts "#{app.name}: Cooldown..."
    sleep 7

    if ENV['DYNO'].blank?
      puts "#{app.name}: Executing postdeploy scripts..."
      app.execute_postdeploy_scripts
    end

    puts "#{app.name}: Setting up dynos..."
    app.setup_dynos

    puts "#{app.name}: Adding to pipeline..."
    app.add_to_pipeline
  end

  Parallel.each(apps.select(&:parallel?)) do |app|
    begin
      process_app.call(app)
    rescue Git::GitExecuteError => e
      puts "#{app.name}: #{e.message}"
    rescue Exception => e
      puts "#{app.name}: #{e.response.body}"
    end
  end

  apps.reject(&:parallel?).each do |app|
    begin
      process_app.call(app)
    rescue Git::GitExecuteError => e
      puts "#{app.name}: #{e.message}"
    rescue Exception => e
      puts "#{app.name}: #{e.response.body}"
    end
  end

  puts "Done."
end

class SignatureError < StandardError
  def message
    'Signatures do not match'
  end
end

class UnsupportedEventError < StandardError; end

class GitHubController
  CMD_TRIGGER = 'reina: d '.freeze

  def initialize(config)
    @config = config
  end

  def dispatch(request)
    @request = request

    authenticate!

    return deploy if deploy_requested?

    raise UnsupportedEventError if event != 'issue_comment'.freeze
  end

  private

  attr_reader :config, :request

  def authenticate!
    hash = OpenSSL::HMAC.hexdigest(hmac_digest, config[:webhook_secret], raw_payload)
    raise SignatureError if "sha1=#{hash}" != signature
  end

  def deploy_requested?
    action == 'created'.freeze && comment_body.start_with?(CMD_TRIGGER)
  end

  def deploy
    args = comment_body
      .lines[0]
      .split(CMD_TRIGGER)[1]
      .split(' ')
      .reject(&:blank?)
      .map { |arg| '"' + arg + '"' }
    args.prepend issue_number.to_s

    cmd = "ruby reina.rb #{args.join(' ')}"
    puts "Executing `#{cmd}` right now..."

    exec cmd
  end

  def signature
    request.env['HTTP_X_HUB_SIGNATURE']
  end

  def event
    request.env['HTTP_X_GITHUB_EVENT']
  end

  def action
    payload['action']
  end

  def issue_number
    payload.dig('issue', 'number')
  end

  def comment_body
    @_comment_body ||= payload.dig('comment', 'body').strip
  end

  def comment_author
    payload.dig('comment', 'user', 'login')
  end

  def payload
    return @_payload if @_payload.present?

    @_payload ||= JSON.parse(raw_payload)
  end

  def raw_payload
    return @_raw_payload if @_raw_payload.present?

    request.body.rewind
    @_raw_payload ||= request.body.read
  end

  def hmac_digest
    @_hmac__digest ||= OpenSSL::Digest.new('sha1')
  end
end

class Server < Sinatra::Base
  set :show_exceptions, false

  error SignatureError do
    halt 403, env['sinatra.error'].message
  end

  error UnsupportedEventError do
    halt 403, env['sinatra.error'].message
  end

  error Exception do
    halt 500, 'Something bad happened... probably'
  end

  get '/' do
    '<img src="https://i.imgur.com/UDxbOsz.png?1">'
  end

  post '/github' do
    GitHubController.new(CONFIG[:github]).dispatch(request)
  end
end

main if __FILE__ == 'reina.rb'
