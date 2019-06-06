module Reina
  class Controller
    class DeploymentError < RuntimeError
      def initialize(app, reason)
        @app = app
        @reason = reason

        sub_msg = reason.respond_to?(:response) ? reason.response.body : reason.message
        super("#{app.name}: #{sub_msg}")
      end

      attr_reader :app, :reason
    end

    APP_COOLDOWN = 7 # seconds

    def initialize(params, strict = false, raise_errors: false)
      @params = params
      @strict = strict
      @raise_errors = raise_errors

      abort 'Please provide $PLATFORM_API' if CONFIG[:platform_api].blank?
      abort 'Given PR number should be greater than 0' if issue_number <= 0

      oversize = apps.select { |app| app.app_name.length >= 30 }.first
      abort "#{oversize.app_name} is too long" if oversize.present?
    end

    def create_netrc
      return if ENV['GITHUB_AUTH'].blank?

      `git config --global user.name "#{ENV['GITHUB_NAME']}"`
      `git config --global user.email "#{ENV['GITHUB_EMAIL']}"`

      return if File.exists?('.netrc')

      File.write(
        '.netrc',
        "machine git.heroku.com login #{ENV['GITHUB_EMAIL']} password #{ENV['HEROKU_API_KEY']}"
      )
    end

    def deploy_parallel_apps!
      Parallel.each(apps.select(&:parallel?)) do |app|
        begin
          deploy!(app)
        rescue Exception => e
          wrapped = DeploymentError.new(app, e)
          raise_errors ? raise(wrapped) : puts(wrapped.message)
        end
      end
    end

    def deploy_non_parallel_apps!
      apps.reject(&:parallel?).each do |app|
        begin
          deploy!(app)
        rescue Exception => e
          wrapped = DeploymentError.new(app, e)
          raise_errors ? raise(wrapped) : puts(wrapped.message)
        end
      end
    end

    def delete_existing_apps!
      existing_apps.each do |app|
        puts "Deleting #{app}"
        heroku.app.delete(app)
      end
    end

    def existing_apps
      # apps in common between heroku's list and ours
      @_existing_apps ||= heroku.app.list.map { |a| a['name'] } & apps.map(&:app_name)
    end

    def heroku?
      ENV['DYNO'].present?
    end

    def apps
      return @_apps if @_apps.present?

      # strict is when we only take in consideration the apps
      # that are in both `params` and `APPS`
      _apps = if strict
        app_names = branches.keys
        APPS.select { |name, _| app_names.include?(name) }
      else
        APPS
      end

      @_apps = _apps.map do |name, project|
        branch = branches[name.to_s].presence || 'master'.freeze
        App.new(heroku, name, project, issue_number, branch)
      end
    end

    private

    attr_reader :params, :strict, :raise_errors

    def heroku
      @_heroku ||= PlatformAPI.connect_oauth(CONFIG[:platform_api])
    end

    def issue_number
      @_issue_number ||= params.shift.to_i
    end

    def branches
      @_branches ||= params.map { |param| param.split('#', 2) }.to_h
    end

    def deploy!(app)
      puts "#{app.name}: Fetching from #{app.project[:github]}..."
      app.fetch_repository
      puts "#{app.name}: HEAD is #{app.g.object('HEAD').sha}"

      puts "#{app.name}: Provisioning #{app.app_name} on Heroku..."
      app.create_app
      app.install_addons
      app.add_buildpacks

      puts "#{app.name}: Waiting for addons..."
      Kernel.sleep APP_COOLDOWN

      app.set_env_vars

      puts "#{app.name}: Deploying to https://#{app.domain_name}..."
      app.deploy

      puts "#{app.name}: Cooldown..."
      Kernel.sleep APP_COOLDOWN

      puts "#{app.name}: Executing postdeploy scripts..."
      app.execute_postdeploy_scripts

      puts "#{app.name}: Setting up dynos..."
      app.setup_dynos

      puts "#{app.name}: Adding to pipeline..."
      app.add_to_pipeline
    end
  end
end
