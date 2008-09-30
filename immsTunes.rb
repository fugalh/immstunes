require 'rubygems' rescue nil
require 'socket'
require 'pathname'
require 'appscript'
require 'logger'
include Appscript

HOME = Pathname.new(ENV['HOME'])
$log = Logger.new STDERR
$log.datetime_format = "%Y-%m-%d %H:%M:%S%Z"

# iTunes isn't a valid class name and ITunes is tacky.
class Tunes < DelegateClass(Appscript::Application)
  # The music library
  attr :library

  # The playlist we manage, e.g. Party Shuffle
  attr :playlist

  def initialize
    @app = app('iTunes')
    super(@app)

    @playlist = @app.playlists[its.special_kind.eq(:Party_Shuffle)].first.get
    @library = @app.library_playlists.first.get

    fixed_indexing.set true
  end
  
  def enqueue(pos)
    t = library.file_tracks[pos].get
    playlist.add t
  end
  
  # This is depressingly inefficient
  def track_by_location(loc)
    loc = MacTypes::Alias.path(loc)
    library.file_tracks.get.find{|t| t.location.get == loc}
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

    # add debug output on @sock.puts
    class << @sock
      def puts(str)
        $log.debug "> #{str.strip}"
        super
      end
      def gets
        str = super
        $log.debug "< #{str.strip}"
        str
      end
    end

    @sock.puts 'Version'
    version = @sock.gets.strip
    unless version == 'Version 2.1'
      $log.warning "I'm not programmed for version #{version}" 
    end

    @sock.puts 'IMMS'
  end

  def dispatch
    until @sock.eof do
      line = @sock.gets.strip

      cmd = line.split.first
      case cmd
      when 'ResetSelection'
        # noop

      when 'TryAgain'
        @sock.puts 'SelectNext'

      when 'EnqueueNext'
        pos = line.split.last.to_i
        @tunes.enqueue pos

      when 'PlaylistChanged'
        $log.error line
        len = line.split.last
        @sock.puts "PlaylistChanged #{len}"

      when 'GetPlaylistItem'
        pos = line.split.last.to_i
        path = @tunes.library.file_tracks[pos].location.get
        @sock.puts "PlaylistItem #{pos} #{path}"

      when 'GetEntirePlaylist'
        @tunes.library.file_tracks.get.each_with_index do |track, pos|
          path = track.location.get 
          @sock.puts "Playlist #{pos} #{path}"
        end
        @sock.puts "PlaylistEnd"

      else
        $log.error "Unknown Command '#{line}'"
      end
    end
  end

  def control
    current_track = nil
    fin = false
    loop do
      # Observe listening behavior
      if @tunes.player_state.get == :playing and not @tunes.mute.get
        t = @tunes.current_track
        p = t.location.get
        if p != current_track
          unless fin
            @sock.puts "EndSong 0 0 0"
          end
          @sock.puts "StartSong #{p}"

          fin = false
          current_track = p
        else
          if not fin and (t.finish.get - @tunes.player_position.get) < 5
            @sock.puts "EndSong 1 0 0"
            fin = true
          end
        end
      end

      # Control playlist
      if @tunes.current_playlist.persistent_ID.get == @tunes.playlist.persistent_ID.get
      end

      sleep 1
    end
  end
end

imms = IMMS.new
Thread.new do
  imms.dispatch
end
imms.control

