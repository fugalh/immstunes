#! /usr/bin/env ruby
require 'pathname'
HOME = Pathname.new(ENV['HOME'])
IO.popen("tail -f -q -n 1 #{HOME + '.imms' + 'imms.log'}", 'r') { |f|
  state = 0
  msg = nil
  f.each_line do |l|
    l.strip!
    if l =~ /Rating: ([\d()]+).*After: ([\d()]+)/
      msg = "Before: #{$1}, After: #{$2}"
      system 'growlnotify', '-m', msg, '-d', 'imms.log', '-p', '-2', '-n', 'IMMS'
      state = 0
    end
  end
}
