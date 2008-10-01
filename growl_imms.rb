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
    if l =~ /Rating: ([^\]]+).*Last: ([^\]]+)(.*)After: ([^\]]+)/
      before = $1
      last = $2
      flags = $3.tr('[]','').strip
      after = $4
      msg = "#{last} #{before} → #{after}\n#{flags}"
      system 'growlnotify', '-m', msg, '-d', 'imms.log', '-p', '-2', '-n', 'IMMS', '--image', Image.to_s, '-w'
      state = 0
    end
  end
}
