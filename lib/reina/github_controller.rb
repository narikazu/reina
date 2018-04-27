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
      elsif issue_closed?
        destroy!
      end
    end

    def deployed_url
      [
        'https://', CONFIG[:app_name_prefix], repo_name, '-', issue_number, '.herokuapp.com'
      ].join
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

    def deploy!
      reina = Controller.new(params)
      should_comment = config[:oauth_token].present?
      reply = ->(msg) { octokit.add_comment(repo_full_name, issue_number, msg) }
      url = deployed_url

      fork do
        reply.call('Starting deployments...') if should_comment

        reina.create_netrc if reina.heroku?
        reina.delete_existing_apps!
        reina.deploy_parallel_apps!
        reina.deploy_non_parallel_apps!

        reply.call("Deployment finished. Live at #{url}.") if should_comment
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
