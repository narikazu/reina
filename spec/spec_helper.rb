require 'reina'

RSpec.configure do |c|
  c.before(:each) do
    config = {
      platform_api: 'platform_api_token',
      app_name_prefix: 'reina-stg-',
      github: {
        webhook_secret: 'secret',
        oauth_token: 'token'
      }
    }

    stub_const('Reina::CONFIG', config)

    apps = {
      searchspot: {
        github: 'honeypotio/searchspot',
        pipeline: 'searchspot',
        config_vars: {
          from: 'staging-searchspot',
          except: ['BONSAI_URL'],
          copy: [
            { from: 'BONSAI_URL', to: 'ES_URL', append: ':443' }
          ]
        }
      }
    }

    stub_const('Reina::APPS', apps)
  end
end
