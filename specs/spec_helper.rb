require_relative '../lib/reina.rb'

RSpec.configure do |c|
  c.before(:each) do
    config = {
      platform_api: 'platform_api_token',
      app_name_prefix: 'reina-stg-'
    }

    stub_const('CONFIG', config)
  end
end
