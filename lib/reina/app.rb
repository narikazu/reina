module Reina
  class App
    DEFAULT_REGION = 'eu'.freeze
    DEFAULT_STAGE  = 'staging'.freeze

    attr_reader :heroku, :name, :project, :issue_number, :branch, :g

    def initialize(heroku, name, project, issue_number, branch)
      @heroku       = heroku
      @name         = name.to_s
      @project      = project
      @issue_number = issue_number
      @branch       = branch
    end

    def fetch_repository
      if Dir.exists?(name)
        @g = Git.open(name)
      else
        @g = Git.clone(github_url, name)
      end

      g.fetch('origin')
      g.checkout("origin/#{branch}", force: true)

      unless g.remotes.map(&:name).include?(remote_name)
        g.add_remote(remote_name, remote_url)
      end
    end

    def create_app
      params = {
        'name'   => app_name,
        'region' => project.fetch(:region, DEFAULT_REGION)
      }

      if team = project[:team]
        heroku.team_app.create(
          params.merge('team' => team)
        )
      else
        heroku.app.create(params)
      end
    end

    def install_addons
      addons = project.fetch(:addons, []) + app_json.fetch('addons', [])
      addons.each do |addon|
        if addon.is_a?(Hash) && addon.has_key?('options')
          addon['config'] = addon.delete('options')
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
            config_vars[h[:to]] = vars_cache[source_app_name].fetch(var)
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
        # Heroku Teams only support hobby and professional dynos.
        h['size'] = project[:team].present? ? 'hobby' : 'free'

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
      local_ref = "origin/#{branch}"

      # Since we're not actually having a local branch and pushing just a ref we
      # have to be explicit about the remote ref.
      remote_ref = 'refs/heads/master'

      g.push(remote_name, "#{local_ref}:#{remote_ref}")
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

    def deployed_url_suffix
      project.fetch(:deployed_url_suffix, '')
    end

    def parallel?
      project[:parallel] != false
    end

    def show_live_url?
      whitelist = CONFIG[:apps_with_live_url]
      return true if whitelist.nil?
      whitelist.include?(name)
    end

    private

    def domain_name_for(s)
      "#{s}.herokuapp.com"
    end

    def app_name_for(s)
      "#{CONFIG[:app_name_prefix]}#{s}-#{issue_number}"
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
