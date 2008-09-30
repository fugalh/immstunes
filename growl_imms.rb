#! /usr/bin/env ruby
require 'pathname'
Image = Pathname.new 'm.png'
HOME = Pathname.new(ENV['HOME'])
IO.popen("tail -f -q -n 1 #{HOME + '.imms' + 'imms.log'}", 'r') { |f|
  state = 0
  msg = nil
  f.each_line do |l|
    l.strip!
    if l =~ /Rating: ([\d()]+).*After: ([\d()]+)/
      msg = "Before: #{$1}, After: #{$2}"
      system 'growlnotify', '-m', msg, '-d', 'imms.log', '-p', '-2', '-n', 'IMMS', '--image', Image.to_s
      state = 0
    end
  end
}
