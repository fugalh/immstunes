require 'rubygems' rescue nil
require 'socket'
require 'pathname'
require 'appscript'
require 'logger'

HOME = Pathname.new(ENV['HOME'])
$log = Logger.new STDERR


# iTunes isn't a valid class name and ITunes is tacky.
# TODO think through this API - how much syntactic sugar?
class Tunes
  include Appscript
  # The music library
  attr :library

  # The playlist we manage, e.g. Party Shuffle
  attr :playlist

  def initialize
    @app = app('iTunes')
    @playlist = @app.playlists[its.special_kind.eq(:Party_Shuffle)].first.get
    @library = @app.library_playlist.first.get
  end
end

class IMMS
  def initialize
    @tunes = Tunes.new

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

    @sock.puts 'IMMS'

    # add debug output on @sock.puts
    class << @sock
      def puts(str)
        $log.debug "> #{str.strip}"
        super
      end
    end

  end

  def dispatch
    Thread.new do
      until @sock.eof
        line = @sock.gets.strip
        $log.debug "< #{line}"
        cmd = line.split.first
        case cmd
        when 'ResetSelection'
          # TODO ???
        when 'TryAgain'
          @sock.puts 'SelectNext'
        when 'EnqueueNext'
          pos = line.split.last.to_i
          @tunes.playlist.add(@tunes.library.tracks[pos].location.get)
        when 'PlaylistChanged'
          $log.error line
          len = line.split.last
          @sock.puts "PlaylistChanged #{len}"
        when 'GetPlaylistItem'
          pos = line.split.last.to_i
          path = @tunes.tracks[pos].location.get
          @sock.puts "PlaylistItem #{pos} #{path}"
        when 'GetEntirePlaylist'
          @tunes.tracks.each_with_index do |track, pos|
            path = track.location.get 
            @sock.puts "Playlist #{pos} #{path}"
          end
          @sock.puts "PlaylistEnd"
        else
          $log.error "Unknown Command #{cmd}"
        end
      end
    end
  end

  def control
    current_track = nil
    fin = false
    loop do
      sleep 1
    end
  end

end

imms = IMMS.new
