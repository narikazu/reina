require_relative 'spec_helper'

describe Reina::GitHubController do
  let(:instance) { described_class.new(CONFIG[:github]) }
  let(:signature) do
    digest = OpenSSL::Digest.new('sha1')
    hash = OpenSSL::HMAC.hexdigest(digest, 'secret', body.dup.read)
    hash.prepend('sha1=')
    hash
  end
  let(:env) do
    { 'HTTP_X_HUB_SIGNATURE' => signature, 'HTTP_X_GITHUB_EVENT' => event }
  end
  let(:comment) { 'reina: d a#b' }
  let(:body) do
    StringIO.new({
      action: action,
      issue: { number: 1234 },
      repository: { name: 'sample', full_name: 'org/sample' },
      comment: {
        body: comment,
        user: { login: 'Rox' }
      }
    }.to_json)
  end
  let(:request) { double('Request', body: body, env: env) }

  describe '#dispatch' do
    subject(:dispatch) { instance.dispatch(request) }

    context 'authentication passes' do
      context 'an issue is created' do
        let(:event) { 'issue_comment' }
        let(:action) { 'created' }

        let(:controller) do
          double('Controller',
            heroku?: false,
            delete_existing_apps!: true,
            deploy_parallel_apps!: true,
            deploy_non_parallel_apps!: true,
            apps: [])
        end
        let(:octokit) { double('Octokit', user: user) }
        let(:user) { double('Octokit', login: true) }
        let(:url) { 'https://reina-stg-sample-1234.herokuapp.com' }

        it 'requests a deploy' do
          expect(instance).to receive(:deploy!)
          expect(instance).to_not receive(:destroy!)
          dispatch
        end

        context 'normal deploy' do
          it 'deploys through a Reina::Controller and replies to the issue' do
            expect(instance).to receive(:fork).and_yield do |ctx|
              expect(Reina::Controller)
                .to receive(:new).with([1234, 'a#b'], false).and_return(controller)

              %i(
                delete_existing_apps! deploy_parallel_apps! deploy_non_parallel_apps! apps
              ).each { |cmd| expect(controller).to receive(cmd).once }
            end

            allow(instance).to receive(:fork)
            allow(Octokit::Client)
              .to receive(:new).with(access_token: 'token').and_return(octokit)
            expect(user).to receive(:login)
            expect(octokit).to receive(:add_comment).with('org/sample', 1234, 'Starting to deploy one app...')
            expect(octokit).to receive(:add_comment).with('org/sample', 1234, "Deployment finished. Live at #{url}/users/login.")

            dispatch
          end
        end

        context 'single deploy' do
          let(:comment) { 'reina: r a#b' }

          it 'deploys through a Reina::Controller and replies to the issue' do
            expect(instance).to receive(:fork).and_yield do |ctx|
              expect(Reina::Controller)
                .to receive(:new).with([1234, 'a#b'], true).and_return(controller)

              %i(
                delete_existing_apps! deploy_parallel_apps! deploy_non_parallel_apps! apps
              ).each { |cmd| expect(controller).to receive(cmd).once }
            end

            allow(instance).to receive(:fork)
            allow(Octokit::Client)
              .to receive(:new).with(access_token: 'token').and_return(octokit)
            expect(user).to receive(:login)
            expect(octokit).to receive(:add_comment).with('org/sample', 1234, 'Starting to deploy one app...')
            expect(octokit).to receive(:add_comment).with('org/sample', 1234, "Deployment finished. Live at #{url}.")

            dispatch
          end
        end
      end

      context 'an issue is closed' do
        let(:event) { 'issues' }
        let(:action) { 'closed' }

        let(:controller) do
          double('Controller',
            heroku?: false,
            existing_apps: existing_apps,
            delete_existing_apps!: true)
        end
        let(:existing_apps) { [1] }
        let(:octokit) { double('Octokit', user: user) }
        let(:user) { double('Octokit', login: true) }

        it 'request for them to be destroyed' do
          expect(instance).to receive(:destroy!)
          expect(instance).to_not receive(:deploy!)
          dispatch
        end

        context 'there are existing apps to be destroyed' do
          it 'destroys them through a Reina::Controller and replies to the issue' do
            expect(Reina::Controller)
              .to receive(:new).with([1234, 'a#b']).and_return(controller)

            expect(instance).to receive(:fork).and_yield do |ctx|
              expect(controller).to receive(:delete_existing_apps!).once
            end

            allow(instance).to receive(:fork)
            allow(Octokit::Client)
              .to receive(:new).with(access_token: 'token').and_return(octokit)
            expect(user).to receive(:login)

            msg = 'All the staging apps related to this issue have been deleted.'
            expect(octokit).to receive(:add_comment).with('org/sample', 1234, msg)

            dispatch
          end
        end

        context 'there are no apps to destroy' do
          let(:existing_apps) { [] }

          it 'does nothing' do
            expect(Reina::Controller)
              .to receive(:new).with([1234, 'a#b']).and_return(controller)

            expect(controller).to_not receive(:delete_existing_apps!)

            expect(instance).to_not receive(:fork)
            expect(Octokit::Client).to_not receive(:new)

            dispatch
          end
        end
      end

      context 'an unexpected action has been taken' do
        let(:event) { 'issues' }
        let(:action) { 'updated' }

        before { allow(instance).to receive(:authenticate!) }

        it 'close the HTTP request silently' do
          expect(instance).to_not receive(:deploy!)
          dispatch
        end
      end

      context 'an unexpected event happened' do
        let(:event) { 'wololo' }
        let(:action) { 'closed' }

        before { allow(instance).to receive(:authenticate!) }

        it 'raises an error' do
          expect { dispatch }.to raise_error(Reina::UnsupportedEventError)
        end
      end
    end
  end
end
