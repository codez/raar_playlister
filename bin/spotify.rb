#!/usr/bin/env ruby

require 'rubygems'
require 'bundler/setup'
Bundler.require(:default)

require 'yaml'
require 'json'

require_relative '../lib/spotify_client'

def settings
  @settings ||= YAML.safe_load(File.read(settings_file)).fetch('spotify')
end

def settings_file
  File.join(File.join(__dir__), '..', 'config', 'settings.yml')
end

client = SpotifyClient.new(settings, STDOUT)
case ARGV[0]
when 'login'
  client.login
when 'refresh_token'
  puts client.fetch_refresh_token(ARGV[1])
else
  puts 'Usage: bin/spotify.rb [login|refresh_token <code>]'
end
