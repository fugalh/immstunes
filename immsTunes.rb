require 'rubygems' rescue nil
require 'socket'
require 'pathname'
require 'appscript'
require 'logger'

HOME = Pathname.new(ENV['HOME'])
$log = Logger.new STDERR

class IMMS
  def initialize
    begin
      @sock = UNIXSocket.open(HOME + '.imms' + 'socket')
    rescue Errno::ECONNREFUSED
      fork do
        exec 'immsd'
      end
      sleep 0.25
      retry
    end

    @sock.puts 'Version'
    version = @sock.gets.strip
    unless version == 'Version 2.1'
      $log.warning "I'm not programmed for version #{version}" 
    end
  end
end

class Tunes
  include Appscript
  def initialize
    @app = app('iTunes')
    @playlist = @app.playlists[its.special_kind.eq(:Party_Shuffle)].first.get
  end
end

imms = IMMS.new
tunes = Tunes.new
