module Reina
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
      hash.prepend('sha1=')
      raise SignatureError unless Rack::Utils.secure_compare(hash, signature)
    end

    def deploy_requested?
      action == 'created'.freeze && comment_body.start_with?(CMD_TRIGGER)
    end

    def deploy
      params = [issue_number]
      params.concat(comment_body
        .lines[0]
        .split(CMD_TRIGGER)[1]
        .split(' ')
        .reject(&:blank?)
        .map { |arg| '"' + arg + '"' })

      fork do
        reina = Controller.new(params)
        reina.create_netrc if reina.heroku?
        reina.delete_existing_apps!
        reina.deploy_parallel_apps!
        reina.deploy_non_parallel_apps!
      end

      if config[:oauth_token].present?
        client = Octokit::Client.new(access_token: config[:oauth_token])
        user = client.user
        user.login

        client.add_comment(repo_full_name, issue_number, reply_message(cmd))
      end
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

    def reply_message(cmd)
      url = ['https://', CONFIG[:app_name_prefix], repo_name, '-', issue_number, '.herokuapp.com'].join
      "`#{cmd}` executed.\n\nWill be deployed at #{url}"
    end

    def comment_body
      payload.dig('comment', 'body').strip
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
