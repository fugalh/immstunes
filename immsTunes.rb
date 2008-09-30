#!/usr/bin/env ruby
require 'rubygems' rescue nil
require 'socket'
require 'pathname'
require 'logger'
require 'thread'
require 'appscript'
include Appscript

HOME = Pathname.new(ENV['HOME'])
$log = Logger.new STDERR
$log.datetime_format = "%Y-%m-%d %H:%M:%S "
$log.level = Logger::WARN
$log.level = Logger::INFO if ARGV.include?('-v')
$log.level = Logger::DEBUG if ARGV.include?('-d')


# iTunes isn't a valid class name and ITunes is tacky.
class Tunes < DelegateClass(Appscript::Application)
  # The music library
  attr :library

  # The playlist we manage, e.g. Party Shuffle
  attr :playlist

  # The list of tracks - NB the indexing is not the same as iTunes'
  attr :tracks

  def initialize
    @app = app('iTunes')
    super(@app)

    @playlist = @app.playlists[its.special_kind.eq(:Party_Shuffle)].first.get
    @library = @app.library_playlists.first.get

    #fixed_indexing.set true
    refresh
  end
  
  def enqueue(track)
    p = track.location.get
    add p, :to => playlist
  end
  
  def refresh
    @tracks = file_tracks.get
  end
  def index(track)
    @tracks.map{|t| t.location.get}.index(track.location.get)
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
      sleep 1
      retry
    end

    # add debug output on @sock.puts
    class << @sock
      def puts(str)
        if str =~ /^Playlist(Item)? /
          $log.debug "> #{str.strip}"
        else
          $log.info "> #{str.strip}"
        end
        super
      end
      def gets
        str = super
        if str =~ /^GetPlaylistItem /
          $log.debug "< #{str.strip}"
        else
          $log.info "< #{str.strip}"
        end
        str
      end
    end

    @mutex = Mutex.new

    @sock.puts 'Version'
    version = @sock.gets.strip
    unless version == 'Version 2.1'
      $log.warning "I'm not programmed for version #{version}. Strange things may happen!" 
    end

    @sock.puts 'IMMS'
    @sock.puts 'Setup 0'
    playlist_changed
  end

  def playlist_changed
    @sock.puts "PlaylistChanged #{@tunes.tracks.size}"
  end

  def dispatch
    until @sock.eof do
      line = @sock.gets.strip

      @mutex.synchronize {
        cmd = line.split.first
        case cmd
        when 'ResetSelection'
          # noop

        when 'TryAgain'
          @sock.puts 'SelectNext'

        when 'EnqueueNext'
          pos = line.split.last.to_i
          t = @tunes.tracks[pos]
          if t.location.get != :missing_value and t.enabled.get and t.shufflable.get
            @next = @tunes.enqueue(t)
          else
            @sock.puts 'SelectNext'
          end

        when 'PlaylistChanged'
          $log.warning line
          @tunes.refresh
          playlist_changed

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
          $log.error "Unknown Command '#{line}'"
        end
      }
    end
  end

  def control
    current_track = nil
    fin = false
    loop do
      @mutex.synchronize {
        # Observe listening behavior
        t = @tunes.current_track
        if @tunes.player_state.get == :playing and not @tunes.mute.get
          p = t.location.get
          if p != current_track
            if not fin and current_track
              @sock.puts "EndSong 0 0 0"
            end
            @sock.puts "StartSong #{@tunes.index(t)} #{p}"

            fin = false
            current_track = p

          else
            f = t.finish.get
            p = @tunes.player_position.get
            if not fin and (f - p) < 5
              @sock.puts "EndSong 1 0 0"
              fin = true
            end
          end
        end

        # Control playlist
        if @tunes.current_playlist.persistent_ID.get == @tunes.playlist.persistent_ID.get
          l = @tunes.playlist.tracks.get.size
          p = t.index.get
          @sock.puts "SelectNext" if p == l
        end
      }

      sleep 1
    end
  end
end

imms = IMMS.new
Thread.new do
  begin
    imms.dispatch
  rescue
    $log.fatal $!
    exit
  end
end
imms.control

# This file is distributed under the Ruby License (http://www.ruby-lang.org/en/LICENSE.txt)
