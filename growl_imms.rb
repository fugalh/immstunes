#! /usr/bin/env ruby
require 'pathname'

Image = Pathname.new($0).dirname + 'm.png'
HOME = Pathname.new(ENV['HOME'])

verbose = ARGV.include? '-v'

IO.popen("tail -f -q -n 1 #{HOME + '.imms' + 'imms.log'}", 'r') { |f|
  state = 0
  msg = nil
  f.each_line do |l|
    puts l if verbose
    l.strip!
    if l =~ /Rating: ([\d()]+).*After: ([\d()]+)/
      msg = "Before: #{$1}, After: #{$2}"
      system 'growlnotify', '-m', msg, '-d', 'imms.log', '-p', '-2', '-n', 'IMMS', '--image', Image.to_s, '-w'
      state = 0
    end
  end
}
