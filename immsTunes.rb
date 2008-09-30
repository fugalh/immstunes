require 'rubygems' rescue nil
require 'socket'
require 'pathname'
require 'appscript'
require 'logger'
include Appscript

HOME = Pathname.new(ENV['HOME'])
iTunes = app('iTunes')
party_shuffle = iTunes.playlists[its.special_kind.eq(:Party_Shuffle)].first.get
imms = nil
begin
  imms = UNIXSocket.open(HOME + '.imms' + 'socket')
rescue Errno::ECONNREFUSED
  fork do 
    exec 'immsd'
  end
  sleep 0.25
  retry
end
log = Logger.new STDERR

imms.puts 'Version'
version = imms.gets.strip
unless version == 'Version 2.1'
  log.warning "I'm not programmed for version #{version}" 
end
puts version
