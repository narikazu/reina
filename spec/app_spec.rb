require 'reina'

describe Reina::App do
  let(:heroku_app) { double('Heroku App') }
  let(:heroku_team_app) { double('Heroku App') }
  let(:heroku_addon) { double('Heroku Addon') }
  let(:heroku_buildpack) { double('Heroku Buildpack Installation') }
  let(:heroku_formation) { double('Heroku Formation') }
  let(:heroku_pipeline) { double('Heroku Pipeline') }
  let(:heroku_pipeline_coupling) { double('Heroku Pipeline Coupling') }
  let(:heroku_config_var) { double('Heroku Config Var') }
  let(:heroku) do
    double('Heroku',
      app: heroku_app,
      team_app: heroku_team_app,
      addon: heroku_addon,
      buildpack_installation: heroku_buildpack,
      formation: heroku_formation,
      pipeline: heroku_pipeline,
      pipeline_coupling: heroku_pipeline_coupling,
      config_var: heroku_config_var
    )
  end
  let(:git) { double('Git', fetch: true, remotes: [], add_remote: true, branch: true, checkout: true) }

  let(:issue_number) { 1234 }
  let(:branch) { 'features/hibike' }
  let(:app) { described_class.new(heroku, :searchspot, Reina::APPS[:searchspot], issue_number, branch) }

  before do
    allow(PlatformAPI).to receive(:connect_oauth).and_return(heroku)
    allow(Git).to receive(:open)
    allow(Git).to receive(:clone)

    allow(app).to receive(:g).and_return(git)

    f = File.read('spec/searchspot/app.json')
    allow(File).to receive(:read).with('searchspot/app.json').and_return(f)
    allow(File).to receive(:exists?).with('searchspot/app.json').and_return(true)
  end

  describe '#fetch_repository' do
    subject(:fetch_repository) { app.fetch_repository }

    context 'folder exists' do
      before { allow(Dir).to receive(:exists?).with('searchspot').and_return(true) }

      it 'opens the git folder' do
        expect(Git).to receive(:open).with('searchspot')
        fetch_repository
      end
    end

    context 'folder does not exists' do
      before { allow(Dir).to receive(:exists?).with('searchspot').and_return(false) }

      it 'clones the git folder' do
        expect(Git).to receive(:clone).with('https://github.com/honeypotio/searchspot', 'searchspot')
        fetch_repository
      end
    end

    it 'pulls from origin/master' do
      expect(git).to receive(:fetch)
      expect(git).to receive(:checkout).with("origin/#{branch}", force: true)
      fetch_repository
    end

    context 'heroku is in the repository\'s remotes' do
      let(:remote) { double('Remote', name: app.remote_name) }
      before { expect(git).to receive(:remotes).and_return([remote]) }

      it 'does not add heroku to the remotes' do
        expect(git).to_not receive(:add_remote)
        fetch_repository
      end
    end

    context 'heroku is not in the repository \'s remotes' do
      it 'adds heroku to the remotes' do
        expect(git).to receive(:add_remote).with(app.remote_name, "https://git.heroku.com/#{app.app_name}.git")
        fetch_repository
      end
    end
  end

  describe '#create_app' do
    subject(:create_app) { app.create_app }

    context 'region is requested' do
      it 'creates a new app on Heroku' do
        Reina::APPS[:searchspot][:region] = 'us'
        expect(heroku_app).to receive(:create).with('name' => app.app_name, 'region' => 'us')
        create_app
      end
    end

    context 'region is not requested' do
      it 'creates a new app on Heroku' do
        Reina::APPS[:searchspot].delete(:region)
        expect(heroku_app).to receive(:create).with('name' => app.app_name, 'region' => 'eu')
        create_app
      end
    end

    context 'team is specified' do
      it 'creates a new app on Heroku' do
        Reina::APPS[:searchspot][:team] = 'foobar'

        expect(heroku_team_app).to receive(:create).with(
          'name' => app.app_name,
          'region' => 'eu',
          'team' => 'foobar'
        )

        create_app
      end
    end

    context 'team is not specified' do
      it 'creates a new app on Heroku' do
        Reina::APPS[:searchspot].delete(:team)

        expect(heroku_app).to receive(:create).with('name' => app.app_name, 'region' => 'eu')

        create_app
      end
    end
  end

  describe '#install_addons' do
    subject(:install_addons) { app.install_addons }

    it 'installs the addons defined in the app.json file' do
      expect(heroku_addon).to receive(:create).with(app.app_name, {
        "plan"   => "bonsai",
        "config" => {
          "version" => "2.4"
        }
      })
      install_addons
    end
  end

  describe '#add_buildpacks' do
    subject(:install_buildpacks) { app.add_buildpacks }

    it 'add the buildpacks defined in the app.json file' do
      expect(heroku_buildpack).to receive(:update).with(app.app_name, {
        'updates' => [
          { 'buildpack' => 'https://github.com/RoxasShadow/heroku-buildpack-rust.git#patch-2' }
        ]
      })
      install_buildpacks
    end
  end

  describe '#set_env_vars' do
    subject(:set_env_vars) { app.set_env_vars }

    it 'set the env vars defined in the config and in the app.json file' do
      allow(heroku_config_var).to receive(:info_for_app).with('staging-searchspot').and_return({
        'BONSAI_URL' => 'blabla'
      })
      expect(heroku_config_var).to receive(:update).with(app.app_name, {
        'ES_URL'   => 'blabla:443',
        'APP_NAME' => 'reina-stg-searchspot-1234',
        'HEROKU_APP_NAME' => 'reina-stg-searchspot-1234',
        'DOMAIN_NAME' => 'reina-stg-searchspot-1234.herokuapp.com',
        'COOKIE_DOMAIN' => '.herokuapp.com',
        'RUST_VERSION' => 'nightly'
      })
      set_env_vars
    end
  end

  describe '#setup_dynos' do
    subject(:setup_dynos) { app.setup_dynos }

    it 'setup the dynos as defined in the app.json file' do
      dyno_opts = { 'quantity' => 1, 'size' => 'free' }
      expect(heroku_formation).to receive(:update).with(app.app_name, 'web', dyno_opts)
      setup_dynos
    end
  end

  describe '#add_to_pipeline' do
    subject(:add_to_pipeline) { app.add_to_pipeline }

    it 'add the app to the pipeline as defined in the app.json file' do
      allow(heroku_pipeline).to receive(:info).with('searchspot').and_return('id' => 1)
      expect(heroku_pipeline_coupling).to receive(:create).with({
        'app'      => app.app_name,
        'pipeline' => 1,
        'stage'    => 'staging'
      })
      add_to_pipeline
    end
  end

  describe '#execute_postdeploy_scripts' do
    subject(:execute_postdeploy_scripts) { app.execute_postdeploy_scripts }

    it 'executes postdeploy scripts' do
      json = app.app_json
      json['scripts'] = { 'postdeploy' => 'kek' }
      expect(app).to receive(:app_json).and_return(json)

      expect(app).to receive(:`).with("heroku run kek --app #{app.app_name}")
      execute_postdeploy_scripts
    end
  end

  describe '#deploy' do
    subject(:deploy) { app.deploy }

    it 'deploys the app to heroku' do
      expect(git).to receive(:push)
        .with("heroku-#{app.app_name}", "origin/#{branch}:refs/heads/master")

      deploy
    end
  end

  describe '#app_name' do
    subject(:app_name) { app.app_name }
    it { is_expected.to eq('reina-stg-searchspot-1234') }
  end

  describe '#show_live_url?' do
    subject { app.show_live_url? }

    it { is_expected.to be_truthy }

    context 'when a whitelist exists' do
      before { allow(Reina::CONFIG).to receive(:[]).and_call_original }

      it 'is true when whitelisted' do
        expect(Reina::CONFIG).to receive(:[]).with(:apps_with_live_url)
          .and_return(["alphabetics", app.name, "other thing"])

        is_expected.to be_truthy
      end

      it 'is false when not whitelisted' do
        expect(Reina::CONFIG).to receive(:[]).with(:apps_with_live_url)
          .and_return(["alphabetics", "other thing"])

        is_expected.to be_falsy
      end
    end
  end

  describe '#remote_name' do
    subject(:remote_name) { app.remote_name }
    it { is_expected.to eq('heroku-reina-stg-searchspot-1234') }
  end
end
