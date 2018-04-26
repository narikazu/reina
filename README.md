Reina - 響け！
-------------

Bot to handle deploys and orchestrations
of feature stagings hosted on Heroku.

Currently in PoC development phase.

It works either as a CLI tool and as a bot having a
server running on Heroku which is hit by GitHub webhooks.

We won't use Heroku's App Setup as it seems to require
the direct URL to the tarball of a repository which is
hard to provide when it is private. So what we do
is parsing ourselves the `app.json` manifest file
while supporting anyway the hardcoded configuration mapping.

Usage
----

As a bot, comment in an issue with: `reina: d "projectzero#nice-feature-branch"`.

As a CLI application, execute `$ ruby reina.rb 1234 "projectzero#nice-feature-branch"`

1234 should be basically the issue or PR number, while for all the app#branch tuples
that are not specified in the command but present in your mapping, those will be
deployed from the `master` branch.

Setup
-----

`$ bundle install && cp config.rb.sample config.rb`

Configure the `APPS` hash map of the `config.rb` file based on your setup.
We can't provide proper documentation for now but with the template we have left
and the source code I hope it will be fine enough for you.

For what concerns the `CONFIG` hash map, this is how you can get the requested tokens:

- `$HEROKU_PLATFORM_API`

```sh
$ heroku login
$ heroku keys:add ~/.ssh/id_rsa.pub
$ heroku plugins:install heroku-cli-oauth
$ heroku authorizations:create -d "Platform API token for Reina"
```

- `$GITHUB_WEBHOOK_SECRET`

This is only needed if you want to run reina as a bot.

From your repository's settings, go to "Hooks" and click the "Add webhook" button.
You will need to set as URL `https://<your_reina_instance_app_name>.herokuapp.com/github`
and grant `issues` and `issue_comment` as permissions.
Set a random and secure secret and share it between the form end the environment variable
we're here talking about.

- `$APP_NAME_PREFIX`

Everything is gonna be fine as app namespace, given it's free on Heroku.

As a bot
--------

First of all, follow the instructions above.

Then you need to provide the following environment variables from Heroku:
- `GITHUB_AUTH` which is your login data to GitHub in the form of `username:password`
- `GITHUB_NAME` which is your GitHub user's login name (protip: create a user meant to be the actual bot - [this is ours](https://github.com/reina-hp))
- `GITHUB_EMAIL` which is your GitHub user's email
- `HEROKU_API_KEY` which is the output of `$ heroku auth:token`

Finally you will need to make a JSON out of the two hash maps in `config.rb` and copy them respectively to the environment variables called `APPS` and `CONFIG`.

If you also want reina to add reply to your request, create an API key to your account (preferabily the one dedicated to the bot you have created before)
with `write:discussion` and `repos` permissions. [Instructions here](https://help.github.com/articles/creating-a-personal-access-token-for-the-command-line/).
Once the key has been generated, set it as `$GITHUB_OAUTH_TOKEN` (or add it to the `config.rb` file).

This is what eventually your environment variables should look like on Heroku: https://i.imgur.com/591bWv7.png

As a bot, due to lack of Heroku CLI in the dyno, post deploy scripts won't be run.

License
-------

Copyright © 2018 Honeypot GmbH.
