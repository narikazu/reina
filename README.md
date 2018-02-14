Reina - 響け！
-------------

Bot to handle deploys and orchestrations
of feature stagings hosted on Heroku.

Currently in PoC development phase.

We won't use Heroku's App Setup as it seems to require
the direct URL to the tarball of a repository which is
hard to provide when it is private.

In any case, we want to support the `app.json` by
parsing it ourselves.

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
