Sinatra, Force.com and Heroku - In Perfect Harmony
==================================================

This app demonstrates how to call the [Force.com REST API](http://developer.force.com/REST) from a [Sinatra](http://www.sinatrarb.com/) app. A couple of additional technologies are used:

* OAuth 2.0 via the [oauth2 gem](https://github.com/intridea/oauth2)
* Persistent Rack sessions in Memcache via [Dalli](https://github.com/mperham/dalli)
* Deployment of the whole shebang on [Heroku](http://www.heroku.com)

Instructions
------------

    $ git clone git://github.com/metadaddy-sfdc/Sinatra-Force.com-Heroku.git
    $ cd Sinatra-Force.com-Heroku
    $ heroku create
    $ heroku addons:add memcache
    $ heroku addons:add ssl:piggyback
    $ git push heroku master
    
Create a remote access app (**App Setup | Develop | Remote Access**) in a Salesforce org with a callback URL of https://YOUR-HEROKU-APP.heroku.com/oauth/callback
    
    $ heroku config:add CLIENT_ID="REMOTE_ACCESS_APP_CONSUMER_KEY" \
    	CLIENT_SECRET="REMOTE_ACCESS_APP_CONSUMER_SECRET" \
    	LOGIN_SERVER="https://login.salesforce.com"

Open https://YOUR-HEROKU-APP.heroku.com/ in a browser