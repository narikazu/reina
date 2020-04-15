require 'reina'

describe Reina::Controller do
  let(:params) { [1234, 'a#b', 'c#d'] }
  let(:strict) { false }
  let(:raise_errors) { false }
  let(:instance) { described_class.new(params, strict, raise_errors: raise_errors) }
  let(:g) { double('Git', object: double('Git::Object', sha: 'abc')) }
  let(:apps) do
    [
      double('App', parallel?: true,
        name: 'first', app_name: 'first_heroku_name', project: {}, domain_name: '', g: g),
      double('App', name: 'second', parallel?: false),
    ]
  end

  before do
    allow(instance).to receive(:apps).and_return(apps)
    allow(instance).to receive(:`)
  end

  describe '#create_netrc' do
    subject(:create_netrc) { instance.create_netrc }

    before do
      stub_const('ENV', {
        'GITHUB_AUTH' => 'gh_auth',
        'GITHUB_NAME' => 'gh_name',
        'GITHUB_EMAIL' => 'gh_email',
        'HEROKU_API_KEY' => 'heroku_auth'
      })
    end

    it 'configures git' do
      allow(File).to receive(:exists?).and_return(true)
      expect(File).to_not receive(:write)
      expect(instance).to receive(:`).with('git config --global user.name "gh_name"')
      expect(instance).to receive(:`).with('git config --global user.email "gh_email"')
      create_netrc
    end

    it 'creates a .netrc file' do
      l = 'machine git.heroku.com login gh_email password heroku_auth'
      expect(File).to receive(:exists?).with('.netrc').and_return(false)
      expect(File).to receive(:write).with('.netrc', l)
      create_netrc
    end
  end

  shared_examples 'handles deployment errors' do
    context 'on error' do
      context 'when raise_errors is true' do
        let(:raise_errors) { true }

        it do
          expect(instance).to receive(:deploy!).and_raise(Git::GitExecuteError, "error")

          expect { subject }.to raise_error do |err|
            expect(err).to be_kind_of(described_class::DeploymentError)
            expect(err.app).to eq(expected_app)
            expect(err.reason.message).to eq(Git::GitExecuteError.new("error").message)
          end
        end
      end

      context 'when raise_errors is false' do
        let(:raise_errors) { false }

        it do
          expect(instance).to receive(:deploy!).and_raise(Git::GitExecuteError, "error")

          expect { subject }.to_not raise_error
        end
      end
    end
  end

  describe '#deploy_parallel_apps' do
    let(:expected_app) { apps[0] }

    subject(:deploy_parallel_apps!) { instance.deploy_parallel_apps! }

    before do
      # Mocking threaded code really hurts
      expect(Parallel).to receive(:each).with([expected_app]) do |args, &block|
        expect(args).to eq([expected_app])
        block.call(*args)
      end
    end

    it 'uses Parallel for apps that do not require any deploment order' do
      expect(instance).to receive(:deploy!).with(expected_app)

      deploy_parallel_apps!
    end

    include_examples "handles deployment errors"
  end

  describe '#deploy_non_parallel_apps' do
    let(:expected_app) { apps[1] }

    subject(:deploy_non_parallel_apps!) { instance.deploy_non_parallel_apps! }

    before { expect(Parallel).to_not receive(:each) }

    it 'skips Parallel and performs deployments one by one' do
      expect(instance).to receive(:deploy!).with(expected_app)
      deploy_non_parallel_apps!
    end

     include_examples "handles deployment errors"
  end

  describe '#branches' do
    subject { instance.send(:branches) }
    it { is_expected.to eq('a' => 'b', 'c' => 'd') }
  end

  describe '#issue_number' do
    subject { instance.send(:issue_number) }
    it { is_expected.to be 1234 }
  end

  describe '#deploy!' do
    let(:app) { apps[0] }
    let(:expected_sleep) { 15 }
    subject(:deploy!) { instance.send(:deploy!, app) }

    before { allow(Kernel).to receive(:sleep).with(expected_sleep) }

    def do_deploy
      %i(
        fetch_repository create_app install_addons add_buildpacks set_env_vars
        deploy execute_postdeploy_scripts setup_dynos add_to_pipeline
      ).each { |cmd| expect(app).to receive(cmd).once }

      deploy!
    end

    it 'executes one by one all the required commands to Reina::App for deploying' do
      do_deploy
    end

    context 'when ENV var for sleep is updated' do
      let(:expected_sleep) { 1337 }

      before do
        allow(ENV).to(
          receive(:fetch)
            .with("APP_COOLDOWN", anything)
            .and_return("1337")
        )
      end

      it 'executes one by one all the required commands to Reina::App for deploying' do
        do_deploy
      end
    end
  end
end
