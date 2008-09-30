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

  def initialize
    @app = app('iTunes')
    super(@app)

    @playlist = @app.playlists[its.special_kind.eq(:Party_Shuffle)].first.get
    @library = @app.library_playlists.first.get

    fixed_indexing.set true
  end
  
  def enqueue(track)
    duplicate track, :to => playlist
  end
  
  def index(track)
    t = tracks[its.persistent_ID.eq(track.persistent_ID.get)].get.first
    if t
      t.index.get
    else
      nil
    end
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
      $log.warn "I'm not programmed for version #{version}. Strange things may happen!" 
    end

    @sock.puts 'IMMS'
    @sock.puts 'Setup 0'
    playlist_changed
  end

  def playlist_changed
    @sock.puts "PlaylistChanged #{@tunes.tracks.last.index.get}"
  end

  def dispatch
    until @sock.eof do
      line = @sock.gets.strip

      @mutex.synchronize {
        cmd = line.split.first
        case cmd
        when 'ResetSelection'
          l = @tunes.playlist.tracks.last
          if loc(l) == @next and @tunes.current_track.index.get != l.index.get
            @tunes.playlist.delete l
          end

        when 'TryAgain'
          @sock.puts 'SelectNext'

        when 'EnqueueNext'
          pos = line.split.last.to_i+1
          t = @tunes.tracks[pos]
          
          if loc(t) != :missing_value and t.enabled.get and t.shufflable.get
            @next = loc(@tunes.enqueue(t))
          else
            @sock.puts 'SelectNext'
          end

        when 'PlaylistChanged'
          $log.warn line
          playlist_changed

        when 'GetPlaylistItem'
          pos = line.split.last.to_i+1
          t = @tunes.tracks[pos]
          path = loc(t)
          @sock.puts "PlaylistItem #{pos-1} #{path}"

        when 'GetEntirePlaylist'
          @tunes.tracks.get.each do |track|
            path = loc(track)
            pos = track.index.get
            @sock.puts "Playlist #{pos-1} #{path}"
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
    # If we happen to play a song not in the library playlist, we'll not tell
    # IMMS about it. (off the record)
    otr = false
    jumped = false
    loop do
      @mutex.synchronize {
        # Observe listening behavior
        t = @tunes.current_track
        playing = (@tunes.player_state.get == :playing)
        if playing and not @tunes.mute.get

          # advance
          p = loc(t)
          if p != current_track
            if not fin and current_track
              @sock.puts "EndSong 0 #{jumped ? 1 : 0} 0" unless otr
            end
            i = @tunes.index(t)
            otr = i.nil?
            @sock.puts "StartSong #{i-1} #{p}" unless otr

            jumped = (p != @next) and @tunes.current_playlist.get == @tunes.playlist.get
            fin = false
            current_track = p

          else
            f = t.finish.get
            p = @tunes.player_position.get
            if not fin and (f - p) < 5
              @sock.puts "EndSong 1 #{jumped ? 1 : 0} 0" unless otr
              fin = true
            end

          end
        end

        # Control playlist
        if playing and @tunes.current_playlist.persistent_ID.get == @tunes.playlist.persistent_ID.get
          l = @tunes.playlist.tracks.get.size
          p = t.index.get
          @sock.puts "SelectNext" if p == l
        end
      }

      sleep 1
    end
  end

  def loc(track)
    begin
      track.location.get
    rescue Appscript::CommandError
      track.name.get
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
