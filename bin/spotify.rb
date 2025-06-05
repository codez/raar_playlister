#!/usr/bin/env ruby

require 'rubygems'
require 'bundler/setup'
Bundler.require(:default)

require 'yaml'
require 'json'

require_relative '../lib/spotify_client'

settings_file = File.join(File.join(__dir__), '..', 'config', 'settings.yml')
settings = YAML.safe_load(File.read(settings_file)).fetch('spotify')
client = SpotifyClient.new(settings, $stdout)

case ARGV[0]
when 'login'
  client.login
  puts 'Please log in to your spotify account and then copy the `code` param from the redirected URL'
when 'refresh_token'
  puts client.fetch_refresh_token(ARGV[1])
else
  puts 'Usage: bin/spotify.rb [login|refresh_token <code>]'
end
