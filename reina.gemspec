Kernel.load 'lib/reina/version.rb'

Gem::Specification.new { |s|
  s.name        = 'reina'
  s.version     = Reina::VERSION
  s.author      = 'Giovanni Capuano'
  s.email       = 'webmaster@giovannicapuano.net'
  s.homepage    = 'http://github.com/honeypotio/reina'
  s.platform    = Gem::Platform::RUBY
  s.summary     = 'Bot to handle deploys and orchestrations of feature stagings hosted on Heroku.'
  s.description = 'Either used as GitHub bot or a CLI tool, reina performs setup and deployment of your applications on Heroku.'
  s.license     = 'BSD-2-Clause'

  s.files         = `git ls-files`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map { |f| File.basename(f) }
  s.require_paths = ['lib']
}
