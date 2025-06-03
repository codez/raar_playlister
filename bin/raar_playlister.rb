#!/usr/bin/env ruby

require 'rubygems'
require 'bundler/setup'
Bundler.require(:default)

require_relative '../lib/playlister'

Playlister.new.run
