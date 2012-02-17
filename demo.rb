require 'rubygems'
require 'sinatra'
require 'oauth2'
require 'json'
require 'cgi'
require 'dalli'
require 'rack/session/dalli' # For Rack sessions in Dalli

$stdout.sync = true

# Dalli is a Ruby client for memcache
def dalli_client
  Dalli::Client.new(nil, :compression => true, :namespace => 'rack.session', :expires_in => 3600)
end

# Use the Dalli Rack session implementation
use Rack::Session::Dalli, :cache => dalli_client

# Set up the OAuth2 client
def oauth2_client
  OAuth2::Client.new(
    ENV['CLIENT_ID'],
    ENV['CLIENT_SECRET'], 
    :site => ENV['LOGIN_SERVER'], 
    :authorize_url =>'/services/oauth2/authorize', 
    :token_url => '/services/oauth2/token',
    :raise_errors => false
  )
end

# Subclass OAuth2::AccessToken so we can do auto-refresh
class ForceToken < OAuth2::AccessToken
  def request(verb, path, opts={}, &block)
    response = super(verb, path, opts, &block)
    if response.status == 401
      puts "Refreshing access token"
      @token = refresh!.token
      response = super(verb, path, opts, &block)
    end
    response
  end
end

# Filter for all paths except /oauth/callback
before do
  pass if request.path_info == '/oauth/callback'
  
  token         = session['access_token']
  refresh       = session['refresh_token']
  @instance_url = session['instance_url']
  
  if token
    @access_token = ForceToken.from_hash(oauth2_client, { :access_token => token, :refresh_token =>  refresh, :header_format => 'OAuth %s' } )
  else
    redirect oauth2_client.auth_code.authorize_url(:redirect_uri => "https://#{request.host}/oauth/callback")
  end  
end

after do
  # Token may have refreshed!
  if session['access_token'] != @access_token.token
    puts "Putting refreshed access token in session"
    session['access_token'] = @access_token.token
  end
end

get '/oauth/callback' do
  begin
    access_token = oauth2_client.auth_code.get_token(params[:code], 
      :redirect_uri => "https://#{request.host}/oauth/callback")

    session['access_token']  = access_token.token
    session['refresh_token'] = access_token.refresh_token
    session['instance_url']  = access_token.params['instance_url']
    
    redirect '/'
  rescue => exception
    output = '<html><body><tt>'
    output += "Exception: #{exception.message}<br/>"+exception.backtrace.join('<br/>')
    output += '<tt></body></html>'
  end
end

get '/' do
  # Field list isn't very volatile - stash it in the session
  if !session['field_list']
    session['field_list'] = @access_token.get("#{@instance_url}/services/data/v21.0/sobjects/Account/describe/").parsed
  end
  
  @field_list = session['field_list']
  
  if params[:value]
    query = "SELECT Name, Id FROM Account WHERE #{params[:field]} LIKE '#{params[:value]}%' ORDER BY Name LIMIT 20"
  else
    query = "SELECT Name, Id from Account ORDER BY Name LIMIT 20"
  end
  
  @accounts = @access_token.get("#{@instance_url}/services/data/v20.0/query/?q=#{CGI::escape(query)}").parsed
  
  erb :index
end

get '/detail' do
  @account = @access_token.get("#{@instance_url}/services/data/v20.0/sobjects/Account/#{params[:id]}").parsed
  
  erb :detail
end

post '/action' do
  if params[:new]
    @action_name = 'create'
    @action_value = 'Create'
    
    @account = Hash.new
    @account['Id'] = ''
    @account['Name'] = ''
    @account['Industry'] = ''
    @account['TickerSymbol'] = ''

    done = :edit
  elsif params[:edit]
    @account = @access_token.get("#{@instance_url}/services/data/v20.0/sobjects/Account/#{params[:id]}").parsed
    @action_name = 'update'
    @action_value = 'Update'

    done = :edit
  elsif params[:delete]
    @access_token.delete("#{@instance_url}/services/data/v20.0/sobjects/Account/#{params[:id]}")
    @action_value = 'Deleted'
    
    @result = Hash.new
    @result['id'] = params[:id]

    done = :done
  end  
  
  erb done
end

post '/account' do
  if params[:create]
    body = {"Name"   => params[:Name], 
      "Industry"     => params[:Industry], 
      "TickerSymbol" => params[:TickerSymbol]}.to_json

    @result = @access_token.post("#{@instance_url}/services/data/v20.0/sobjects/Account/", 
      {:body => body, 
       :headers => {'Content-type' => 'application/json'}}).parsed
    @action_value = 'Created'
  elsif params[:update]
    body = {"Name"   => params[:Name], 
      "Industry"     => params[:Industry], 
      "TickerSymbol" => params[:TickerSymbol]}.to_json

    # No response for an update
    @access_token.post("#{@instance_url}/services/data/v20.0/sobjects/Account/#{params[:id]}?_HttpMethod=PATCH", 
      {:body => body, 
       :headers => {'Content-type' => 'application/json'}})
    @action_value = 'Updated'
    
    @result = Hash.new
    @result['id'] = params[:id]
  end  
  
  erb :done
end

get '/logout' do
  # First kill the access token
  # (Strictly speaking, we could just do a plain GET on the revoke URL, but
  # then we'd need to pull in Net::HTTP or somesuch)
  @access_token.get(ENV['LOGIN_SERVER']+'/services/oauth2/revoke?token='+session['access_token'])
  # Now save the logout_url
  @logout_url = session['instance_url']+'/secur/logout.jsp'
  # Clean up the session
  session['access_token'] = nil
  session['instance_url'] = nil
  session['field_list'] = nil
  # Now give the user some feedback, loading the logout page into an iframe...
  erb :logout
end

get '/revoke' do
  # For testing - revoke the token, but leave it in place, so we can test refresh
  @access_token.get(ENV['LOGIN_SERVER']+'/services/oauth2/revoke?token='+session['access_token'])
  puts "Revoked token #{@access_token.token}"
  "Revoked token #{@access_token.token}"
end
