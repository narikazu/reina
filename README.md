Reina - 響け！
-------------

Bot to handle deploys and orchestrations
of feature stagings hosted on Heroku.

Currently in PoC development phase.

Setup
-----

`$ bundle install`


`$ cp .env.sample .env`


`$ heroku login`


`$ heroku keys:add ~/.ssh/id_rsa.pub`


`$ heroku plugins:install heroku-cli-oauth`


`$ heroku authorizations:create -d "Platform API token for Reina"`

License
-------

Copyright © 2018 Honeypot GmbH.
