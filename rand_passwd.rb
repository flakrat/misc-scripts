#!/usr/bin/ruby -w
#-----------------------------------------------------------------------------
# Name        :  rand_passwd.rb
# Author      :  Mike Hanby < mhanby at uab.edu >
# Organization:  University of Alabama at Birmingham IT Research Computing
# Description :  This script will generate a random password of the requested
#     length
#                 
# Usage       :  $0 --length 10
# Date        :  2012-06-04 10:30:19
# Type        :  Utility
#
#-----------------------------------------------------------------------------
# History
# 20120604 - mhanby - Initial creation of script
require 'optparse' # CLI Option Parser

copywrite = 'Copyright (c) 2012 Mike Hanby, University of Alabama at Birmingham IT Research Computing.'

options = Hash.new # Hash to hold options parsed from CLI

optparse = OptionParser.new()  do |opts|
  # Help screen banner
  opts.banner = <<EOF
  #{copywrite}
  
  Generates a random password

EOF
  
  # User ID
  options[:length] = nil
  opts.on('-l', '--length N', Integer,
          'Number of characters to use for password. Default is 10') do |o|
    options[:length] = o
  end
 
  # help
  options[:help] = false
  opts.on('-?', '-h', '--help', 'Display this help screen') do
    puts opts
    exit
  end
end
# end optparse

# parse! removes the processed args from ARGV, leaving any extras for additional parsing of ARGV
optparse.parse!

# Generate a random password
def rand_passwd(length=10)
  length.is_a?(Integer) ? length : length = 10

  # I omitted characters from the array that could be confusing (i.e. 1  and l)
  #   chars = %w(A B C D E F G H I J K L M N O
  #              P Q R S T U V W X Y Z
  #              a b c d e f g h i j k l m n o
  #              p q r s t u v w x y z
  #              @ . \$ # , - _ %
  #              0 1 2 3 4 5 6 7 8 9)
  chars = Array.new
  chars = %w(A B C D E F G H J K M N
             P Q R S T U V W X Y Z
             a b c d e f g h i j k m n
             p q r s t u v w x y z
             2 3 4 5 6 7 8 9 , @ .)
  passwd = ''
  length.times do
    passwd += chars[rand(chars.length)]
  end
  return passwd
end
# end rand_passwd()

puts options[:length]? rand_passwd(options[:length]) : rand_passwd