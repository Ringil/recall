#!/usr/bin/env ruby
#Add omniauth and email out reminders

require 'sinatra'
require 'pony'
require 'data_mapper'
require 'time'
require 'sinatra/flash'
require 'sinatra/redirect_with_flash'
require 'omniauth'
require 'omniauth-twitter'

SITE_TITLE = "Recall"
SITE_DESCRIPTION = "'cause you're too busy to remember"
TWITTER_CONSUMER_KEY = '2lvtFdUPPtVTXTftGzfPg'
TWITTER_CONSUMER_SECRET = 'UzrUxqwxloMlV39n3cvUCSgDGJWJH2rWo6nlmks0Mo'

enable :sessions

use OmniAuth::Builder do
    provider :twitter, TWITTER_CONSUMER_KEY, TWITTER_CONSUMER_SECRET
end


#REMEMBER TO SWITCH THE DB WHEN PUSHING TO HEROKU
#DataMapper.setup(:default, "sqlite3://#{Dir.pwd}/recall.db")
DataMapper.setup(:default, ENV['DATABASE_URL'])

class Note
	include DataMapper::Resource
	property :id, Serial, unique_index: true
    #property :owner, Text, :required => true
	property :content, Text, :required => true
	property :complete, Boolean, :required => true, :default => false
	property :created_at, DateTime
	property :updated_at, DateTime
	belongs_to :user
end

class User
  include DataMapper::Resource
  property :id,         Serial
  property :uid,        String
  property :name,       String
  property :nickname,   String
  property :created_at, DateTime
  has n, :notes
end

DataMapper.finalize.auto_upgrade!

helpers do
	include Rack::Utils
	alias_method :h, :escape_html
end

helpers do
  def current_user
    @current_user ||= User.get(session[:user_id]) if session[:user_id]
  end
end

# 
# Application
#

get '/' do
    if current_user
        @notes = User.get(session[:user_id]).Note.all :order => :id.desc
	    @title = 'All Notes'
	    if @notes.empty?
		    flash[:error] = 'No notes found. Add your first below.'
	    end 
	    erb :home
    else
        @title = "Sign in"
        erb :signin
    end
end

post '/' do
	n = Note.new
	n.attributes = {
		:content => params[:content],
		:created_at => Time.now,
		:updated_at => Time.now
	}
	if n.save
		redirect '/', :notice => 'Note created successfully.'
	else
		redirect '/', :error => 'Failed to save note.'
	end
end

get '/auth/:name/callback' do
  auth = request.env["omniauth.auth"]
  user = User.first_or_create({ :uid => auth["uid"]}, {
    :uid => auth["uid"],
    :nickname => auth["info"]["nickname"], 
    :name => auth["info"]["name"],
    :created_at => Time.now })
  session[:user_id] = user.id
  redirect '/'
end

# any of the following routes should work to sign the user in: 
#   /sign_up, /signup, /sign_in, /signin, /log_in, /login
["/sign_in/?", "/signin/?", "/log_in/?", "/login/?", "/sign_up/?", "/signup/?"].each do |path|
  get path do
    redirect '/auth/twitter'
  end
end

# either /log_out, /logout, /sign_out, or /signout will end the session and log the user out
["/sign_out/?", "/signout/?", "/log_out/?", "/logout/?"].each do |path|
  get path do
    session[:user_id] = nil
    redirect '/'
  end
end

get '/rss.xml' do
	@notes = Note.all :order => :id.desc
	builder :rss
end

get '/:id' do
	@note = Note.get params[:id]
	@title = "Edit note ##{params[:id]}"
	if @note
		erb :edit
	else
		redirect '/', :error => "Can't find that note."
	end
end

put '/:id' do
	n = Note.get params[:id]
	unless n
		redirect '/', :error => "Can't find that note."
	end
	n.attributes = {
		:content => params[:content],
		:complete => params[:complete] ? 1 : 0,
		:updated_at => Time.now
	}
	if n.save
		redirect '/', :notice => 'Note updated successfully.'
	else
		redirect '/', :error => 'Error updating note.'
	end
end

get '/:id/delete' do
	@note = Note.get params[:id]
	@title = "Confirm deletion of note ##{params[:id]}"
	if @note
		erb :delete
	else
		redirect '/', :error => "Can't find that note."
	end
end

delete '/:id' do
	n = Note.get params[:id]
	if n.destroy
		redirect '/', :notice => 'Note deleted successfully.'
	else
		redirect '/', :error => 'Error deleting note.'
	end
end

get '/:id/complete' do
	n = Note.get params[:id]
	unless n
		redirect '/', :error => "Can't find that note."
	end
	n.attributes = {
		:complete => n.complete ? 0 : 1, # flip it
		:updated_at => Time.now
	}
	if n.save
		redirect '/', :notice => 'Note marked as complete.'
	else
		redirect '/', :error => 'Error marking note as complete.'
	end
end

post '/:id/remind' do
    Pony.mail(:to => 'kylerob89@gmail.com',
              :subject => 'Reminder:',
              :body => 'Right now this is a generic reminder!')
end
