module Reina
  class SignatureError < StandardError
    def message
      'Signatures do not match'
    end
  end

  class UnsupportedEventError < StandardError; end

  class GitHubController
    DEPLOY_TRIGGER = 'reina: d '.freeze
    SINGLE_DEPLOY_TRIGGER = 'reina: r '.freeze
    EVENTS = %w(issues issue_comment).freeze

    def initialize(config)
      @config = config
    end

    def dispatch(request)
      @request = request

      raise UnsupportedEventError unless EVENTS.include?(event)

      authenticate!

      if deploy_requested?
        deploy!
      elsif single_deploy_requested?
        deploy!(true)
      elsif issue_closed?
        destroy!
      end
    end

    def deployed_app_name(app)
      "#{CONFIG[:app_name_prefix]}#{app}-#{issue_number}"
    end

    def deployed_url(app)
      "https://#{deployed_app_name(app)}.herokuapp.com/#{app.deployed_url_suffix}"
    end

    def heroku_url(app, path = "")
      "https://dashboard.heroku.com/apps/#{deployed_app_name(app)}/#{path}"
    end

    private

    attr_reader :config, :request

    def authenticate!
      hash = OpenSSL::HMAC.hexdigest(hmac_digest, config[:webhook_secret], raw_payload)
      hash.prepend('sha1=')
      raise SignatureError unless Rack::Utils.secure_compare(hash, signature)
    end

    def deploy_requested?
      action == 'created'.freeze && comment_body.start_with?(DEPLOY_TRIGGER)
    end

    def single_deploy_requested?
      action == 'created'.freeze && comment_body.start_with?(SINGLE_DEPLOY_TRIGGER)
    end

    def issue_closed?
      action == 'closed'.freeze
    end

    def deploy!(strict = false)
      reina = Controller.new(params, strict)
      should_comment = config[:oauth_token].present?
      reply = ->(msg) { octokit.add_comment(repo_full_name, issue_number, msg) }

      deploy_finished_message = if should_comment
        message = "Finished deploying.\n\n"

        reina.apps.map do |app|
          message << "- #{app.name} -- [Live url](#{deployed_url(app)}) \
            [Heroku](#{heroku_url(app)}) \
            [Settings](#{heroku_url(app, "settings")}) \
            [Logs](#{heroku_url(app, "logs")}).\n"
        end

        message
      end

      fork do
        apps_count = reina.apps.size

        if should_comment
          if apps_count > 1
            reply.call("Starting to deploy #{apps_count} apps...")
          else
            reply.call("Starting to deploy one app...")
          end
        end

        reina.create_netrc if reina.heroku?
        reina.delete_existing_apps!
        reina.deploy_parallel_apps!
        reina.deploy_non_parallel_apps!

        reply.call(deploy_finished_message) if should_comment
      end
    end

    def destroy!
      reina = Controller.new(params)
      return if reina.existing_apps.empty?

      should_comment = config[:oauth_token].present?
      reply = ->(msg) { octokit.add_comment(repo_full_name, issue_number, msg) }

      fork do
        reina.create_netrc if reina.heroku?
        reina.delete_existing_apps!

        reply.call('All the staging apps related to this issue have been deleted.') if should_comment
      end
    end

    def octokit
      return @_octokit if @_octokit.present?

      client = Octokit::Client.new(access_token: config[:oauth_token])
      user = client.user
      user.login
      @_octokit = client
    end

    def params
      return [issue_number] if comment_body.blank?

      [
        issue_number,
        comment_body
          .lines[0]
          .split(/#{DEPLOY_TRIGGER}|#{SINGLE_DEPLOY_TRIGGER}/)[1]
          .split(' ')
          .reject(&:blank?)
      ].flatten
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

    def repo_name
      payload.dig('repository', 'name')
    end

    def repo_full_name
      payload.dig('repository', 'full_name')
    end

    def comment_body
      payload.dig('comment', 'body')&.strip.to_s
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
      @_hmac_digest ||= OpenSSL::Digest.new('sha1')
    end
  end
end
