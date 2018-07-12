module Reina
  class App
    DEFAULT_REGION = 'eu'.freeze
    DEFAULT_STAGE  = 'staging'.freeze
    DEFAULT_APP_NAME_PREFIX = CONFIG[:app_name_prefix].freeze

    attr_reader :heroku, :name, :project, :issue_number, :branch, :g

    def initialize(heroku, name, project, issue_number, branch)
      @heroku       = heroku
      @name         = name.to_s
      @project      = project
      @issue_number = issue_number
      @branch       = branch
    end

    def fetch_repository
      base_dir = '/tmp/checkouts/'
      dir = base_dir + name
      if Dir.exists?(dir)
        Dir.delete(dir)
      end

      @g = Git.clone(github_url, name, { :path => base_dir })

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

          if var == 'url'.freeze
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
      config_vars['COOKIE_DOMAIN']   = '.herokuapp.com'.freeze

      app_json.fetch('env', {}).each do |key, hash|
        next if hash['value'].blank? || config_vars[key].present?
        config_vars[key] = hash['value']
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

      return if heroku? && ENV['HEROKU_API_KEY'].blank?

      `heroku run #{script} --app #{app_name}`
    end

    def deploy
      g.push(remote_name, "#{branch}:master")
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
      "#{DEFAULT_APP_NAME_PREFIX}#{s}-#{issue_number}"
    end

    def github_url
      return "https://github.com/#{project[:github]}" if ENV['GITHUB_AUTH'].blank?

      "https://#{ENV['GITHUB_AUTH']}@github.com/#{project[:github]}"
    end

    def remote_url
      "https://git.heroku.com/#{app_name}.git"
    end

    def heroku?
      ENV['DYNO'].present?
    end
  end
end
