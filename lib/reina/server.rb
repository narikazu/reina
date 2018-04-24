module Reina
  class Server < Sinatra::Base
    set :show_exceptions, false

    error SignatureError do
      halt 403, env['sinatra.error'].message
    end

    error UnsupportedEventError do
      halt 403, env['sinatra.error'].message
    end

    error Exception do
      halt 500, 'Something bad happened... probably'
    end

    get '/' do
      '<img src="https://i.imgur.com/UDxbOsz.png?1">'
    end

    post '/github' do
      GitHubController.new(CONFIG[:github]).dispatch(request)
      status 202
      body ''
    end
  end
end
