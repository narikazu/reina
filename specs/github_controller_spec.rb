require_relative 'spec_helper'

describe Reina::GitHubController do
  let(:instance) { described_class.new(CONFIG[:github]) }
  let(:event) { 'issue_comment' }
  let(:signature) { 'sha1=f31ae23e955f73b84b4b2dc6dad38ab6b27a79ea' }
  let(:env) do
    { 'HTTP_X_HUB_SIGNATURE' => signature, 'HTTP_X_GITHUB_EVENT' => event }
  end
  let(:comment) { 'reina: d a#b' }
  let(:action) { 'created' }
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

    context 'authentication fails' do
      let(:comment) { 'wololo' }

      it 'raises an error' do
        expect { dispatch }.to raise_error(Reina::SignatureError)
      end
    end

    context 'authentication passes' do
      context 'an issue is created' do
        let(:controller) do
          double('Controller',
            heroku?: false,
            delete_existing_apps!: true,
            deploy_parallel_apps!: true,
            deploy_non_parallel_apps!: true)
        end
        let(:octokit) { double('Octokit', user: user) }
        let(:user) { double('Octokit', login: true) }
        let(:msg) { 'Deployment started at https://reina-stg-sample-1234.herokuapp.com...' }

        it 'requests a deploy' do
          expect(instance).to receive(:deploy!)
          dispatch
        end

        it 'creates a Reina::Controller and replies to the issue' do
          expect(instance).to receive(:fork).and_yield do |ctx|
            expect(Reina::Controller)
              .to receive(:new).with([1234, '"a#b"']).and_return(controller)

            %i(
              delete_existing_apps! deploy_parallel_apps! deploy_non_parallel_apps!
            ).each { |cmd| expect(controller).to receive(cmd).once }
          end

          allow(instance).to receive(:fork)
          allow(Octokit::Client)
            .to receive(:new).with(access_token: 'token').and_return(octokit)
          expect(user).to receive(:login)
          expect(octokit).to receive(:add_comment).with('org/sample', 1234, msg)

          dispatch
        end

      end

      context 'an unexpected action has been taken' do
        let(:action) { 'updated' }

        before { allow(instance).to receive(:authenticate!) }

        it 'close the HTTP request silently' do
          expect(instance).to_not receive(:deploy!)
          dispatch
        end
      end

      context 'an unexpected event happened' do
        let(:event) { 'wololo' }

        before { allow(instance).to receive(:authenticate!) }

        it 'raises an error' do
          expect { dispatch }.to raise_error(Reina::UnsupportedEventError)
        end
      end
    end
  end
end
