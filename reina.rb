require 'bundler'
Bundler.require

CONFIG = {
  platform_api: ENV['PLATFORM_API']
}

heroku = PlatformAPI.connect_oauth(CONFIG[:platform_api])

APPS = {
  searchspot: {
    github: 'honeypotio/searchspot',
    pipeline: 'searchspot',
    config_vars: {
      from: 'staging-searchspot',
      except: ['BONSAI_URL'],
      copy: [
        { from: 'BONSAI_URL', to: 'ES_URL', append: ':443' }
      ]
    }
  },

  honeypot: {
    github: 'honeypotio/honeypot',
    pipeline: 'honeypot',
    config_vars: {
      from: 'replica-production-honeypot',
      except: ['BUILDPACK_URL', 'DATABASE_URL', 'REDIS_URL', 'SEED_MODELS'],
      copy: [
        { from: 'searchspot#url', to: 'SEARCHSPOT_URL' }
      ]
    }
  },

  'admin-honeypot'.to_sym => {
    github: 'honeypotio/admin_active',
    pipeline: 'admin-honeypot',
    config_vars: {
      from: 'staging-admin-honeypot',
      copy: [
        { from: 'honeypot#url',          to: 'APP_HOST' },
        { from: 'honeypot#DATABASE_URL', to: 'DATABASE_URL' },
        { from: 'honeypot#REDIS_URL',    to: 'REDIS_URL' },
        { from: 'searchspot#url',        to: 'SEARCHSPOT_URL' }
      ]
    }
  }
}

abort 'Please provide $PLATFORM_API' if CONFIG[:platform_api].blank?

class App
  attr_reader :heroku, :name, :project, :pr_number, :g

  def initialize(heroku, name, project, pr_number)
    @heroku    = heroku
    @name      = name.to_s
    @project   = project
    @pr_number = pr_number
  end

  def fetch_repository
    if Dir.exists?(name)
      @g = Git.open(name)
    else
      @g = Git.clone("https://github.com/#{project[:github]}", name)
    end

    g.pull('origin', 'master')

    unless g.remotes.map(&:name).include?(remote_name)
      g.add_remote(remote_name, "git@heroku.com:#{app_name}.git")
    end
  end

  def create_app
    heroku.app.create(
      'name'   => app_name,
      'region' => project.fetch(:region, 'eu')
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

    if config_vars.has_key?(:from)
      except = config_vars[:except]
      copy = config_vars.fetch(:copy, []) # this should be dropped...
      config_vars = heroku.config_var.info_for_app(config_vars[:from])

      vars_cache = {}
      copy.each do |h|
        if h[:from].include?('#')
          source, var = h[:from].split('#')
          source_app_name = app_name_for(source)
          if var == 'url'
            config_vars[h[:to]] = "https://#{domain_name_for(source_app_name)}"
          else
            vars_cache[source_app_name] ||= heroku.config_var.info_for_app(source_app_name)
            config_vars[h[:to]] = vars_cache[source_app_name][var]
          end
        else
          s = config_vars[h[:from]]
          s << h[:append] if h.has_key?(:append)
          config_vars[h[:to]] = s
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

  def setup_dyno
    app_json.fetch('formation', {}).each do |k, h|
      heroku.formation.update(app_name, k, h)
    end
  end

  def add_to_pipeline
    return if project[:pipeline].blank?

    pipeline_id = heroku.pipeline.info(project[:pipeline])['id']
    heroku.pipeline_coupling.create(
      'app'      => app_name,
      'pipeline' => pipeline_id,
      'stage'    => 'staging'
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

  private

  def domain_name_for(s)
    "#{s}.herokuapp.com"
  end

  def app_name_for(s)
    "reina-stg-#{s}-#{pr_number}"
  end
end

APPS.each do |name, project|
  app = App.new(heroku, name, project, 1)
  abort '#{app.app_name} is too long pls send help' if app.app_name.length >= 30

  puts "Fetching #{project[:github]}..."
  app.fetch_repository

  puts "Provisioning #{app.app_name} on Heroku..."
  app.create_app
  app.install_addons
  app.add_buildpacks
  app.set_env_vars

  puts "Deploying #{app.app_name} on https://#{app.app_name}.herokuapp.com..."
  app.deploy

  puts 'Cooldown...'
  sleep 7

  puts "Executing postdeploy scripts..."
  app.execute_postdeploy_scripts

  app.setup_dyno

  app.add_to_pipeline
end if __FILE__ == 'reina.rb'
