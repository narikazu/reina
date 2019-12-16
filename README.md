Reina - 響け！
-------------

[![Gem Version](https://badge.fury.io/rb/reinarb.svg)](https://badge.fury.io/rb/reinarb)
[![CircleCI](https://circleci.com/gh/honeypotio/reina.svg?style=svg)](https://circleci.com/gh/honeypotio/reina)

GitHub bot and CLI application to handle deployments and
orchestrations of feature stagings on Heroku.

We won't use Heroku's App Setup as it seems to require
the direct URL to the tarball of a repository which is
hard to provide when it is private. So we do pretty much
everything manually in the code base.

Use case
--------
TL;DR: You can deploy different branches, on Heroku, of different projects that rely on each other
and get them connected through environment variables.

As you can see from the template of the configuration, at Honeypot we have four main applications
that make the whole architecture work as intended.

This is nice and fine in production and in the main staging, but it's not that simple with the feature stagings
provided by Heroku (basically everytime you open a pull request against a repository a fresh and temporary
staging environment gets automatically created).

Until a couple of months ago, the admin and the frontend apps were located in the main back-end repository,
while a single [searchspot](https://github.com/honeypotio/searchspot) instance was shared among the other
feature stagings, with all the obvious indexing problem that you can imagine from such a setup.

By moving the frontend app to another repository, we basically had the need to modify manually the environment
variables to connect it to the back-end everytime we had to do QA for a change that must be present on both
the sides.

Sure thing, Kubernetes and similar applications are possibily a good solutions for similar cases but preferred
to continue using a testing architecture similar to the one we were used to since it always well suited our methodologies
without adding additional layers we hadn't experience at or moving to other testing solutions.

So we ended up with reina, which basically allows us to replace Heroku's feature stagings by adding a good amount
of customizations and nice things. We are sure other solutions do exist, but reina seems working good for us from
quite some time. It's not hard to set it up as a bot and hopefully can help anyone else that get into a situation
similar to ours. Feel free to open an issue for anything or submit a pull request if you need something from her to do!

Usage
----

There are two ways to use reina: as a github bot or as a CLI-app.

When used as a bot, just leave a comment in an issue like `reina: d projectzero#nice-feature-branch`.
Reina will handle all the cleaning once you eventually close it.
By executing once again the command, the stagings will be replaced with a fresh new deploy. If a branch is not specified, it will automatically deploy the latest master branch for each supported project.

You can also replace the `d` with `r` (as in `reina: r projectzero#nice-feature-branch`) when you want
to enable the `strict` mode which re-deploys only the apps that you have explicitly specified in the command
which is useful when you want to deploy only the latest version of an application that you have already
deployed rather than the whole suite (to save time).

As a CLI application, execute `$ reina 1234 "projectzero#nice-feature-branch"`.

`$ reina -h` will show the usage infos in order to enable things like the above mentioned `strict` mode.

In the example command mentioned before, `1234` would basically be the issue number, while for all
the `app#branch` tuples that are not specified in the command but present in your mapping (`config.rb`),
 will be deployed from the `master` branch (which is the same of what happens with the bot usage btw).

Setup
-----

Install the gem which will provide you both the executable and the library: `$ gem install reinarb`.

Then, copy somewhere in your machine the `config.rb.sample` file that you can find here
in this repository  and rename it as `config.rb`.

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

Everything is gonna be fine as app namespace, unless the eventual generated app name has already
been used by someone on Heroku.

As a bot
--------

First of all, follow the instructions above, then host the bot as a rack application on Heroku.

Then you need to provide the following environment variables from Heroku:
- `GITHUB_AUTH` which is your login data to GitHub in the form of `username:password`
- `GITHUB_NAME` which is your GitHub user's login name (protip: create a user meant to be the actual bot - [this is ours](https://github.com/reina-hp))
- `GITHUB_EMAIL` which is your GitHub user's email
- `HEROKU_API_KEY` which is the output of `$ heroku auth:token`

Finally you will need to make a JSON out of the two hash maps in `config.rb` and copy them respectively to the environment variables called `APPS` and `CONFIG` (typing `require 'json'; puts APPS; puts CONFIG` should be enough to get what you need).

If you also want Reina to add replies to your request, create an API key for your account (preferabily the one dedicated to the bot you have created before) with `write:discussion` and `repos` permissions. [Instructions here](https://help.github.com/articles/creating-a-personal-access-token-for-the-command-line/).
Once the key has been generated, set it as `GITHUB_OAUTH_TOKEN` (or add it to the `config.rb` file).

This is what eventually your environment variables should look like on Heroku: https://i.imgur.com/zx4cHWB.png

License
-------

Copyright © 2018 Honeypot GmbH.
