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

Open https://YOUR-HEROKU-APP.heroku.com/ in a browser. Log in with a Salesforce username/password and you should see a list of 20 accounts. You can create/read/update/delete.

The app is deployed at https://warm-dawn-1409.heroku.com/ - you can go there and log in with Salesforce credentials to browser the Accounts in your org.

How It Works
------------

Most of the action is in `demo.rb`. The `before` filter checks whether there is an OAuth access token in the session. If there is, then it creates an OAuth2::AccessToken object from the stored data, otherwise, it renders the `auth.rb` view, which checks if the browser connected via https. If the connection is secure, the browser is redirected to authenticate at salesforce.com, otherwise an error message is shown.

On authenticating the user and obtaining the user's consent for the app to access the user's data, Salesforce redirects the browser back to `/oauth/callback`, where the handler extracts the `code` query parameter and uses the OAuth2 library to obtain an access token. The access token and instance URL are saved to the session, and the browser is redirected to `/`.

Note, near the top of `demo.rb`:

    # Dalli is a Ruby client for memcache
    def dalli_client
      Dalli::Client.new(nil, :compression => true, :namespace => 'rack.session', :expires_in => 3600)
    end

    # Use the Dalli Rack session implementation
    use Rack::Session::Dalli, :cache => dalli_client

This code creates a Dalli client with which to interact with memcache, and sets it as the Rack session handler. In contrast to Rack's default cookie-based sessions, sessions in memcache are independent of the Ruby server process, can be load-balanced across server instances, and survive restart of the server.

The `/` handler calls `describe` on the `Account` object, and caches the result in the session, since this is relatively static data. Next, it retrieves a list of accounts from Salesforce via the access token's `get` method, and renders a page via `erb`. The index page shows a dropdown list of fields on which the user can search, and a list of 20 accounts that match the search parameters.

The handler for `/detail` simply retrieves a single Account record and renders a subset of its data via `detail.erb`. The `/action` and `/account` handlers render pages for creating and updating records, and apply those actions to the Account record respectively. The OAuth2::AccessToken methods make it very easy to manipulate records via the REST API.

Finally, the `/logout` handler revokes the access token, cleans up the session, and logs the user out via the browser. Note the use of an invisible iframe in `logout.erb` to terminate the browser session.

Conclusion
----------

This sample app demonstrates how to interact with the Force.com REST API from a Sinatra app via the OAuth2 library. It shows how to use Dalli with memcache to implement persistent sessions, and how Heroku makes deployment almost effortless.