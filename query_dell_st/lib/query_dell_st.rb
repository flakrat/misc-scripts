#!/usr/bin/ruby -w
#-----------------------------------------------------------------------------
# Name        :  query_dell_st.rb
# Author      :  Mike Hanby <mhanby@uab.edu>
# Organization:  University of Alabama at Birmingham IT Research Computing
# Description :  Queries Dell Support site to obtain Model and Warranty
#   status for given service tag
#                 
# Usage       :  N/A
# Date        :  2012-05-02 14:58:18
# Type        :  Tool
#-----------------------------------------------------------------------------
# History
# 20120507 - mhanby - Added new cli option: --format that allows for output in
#   csv or tab delimited format
# 20120502 - mhanby - Initial creation of script. Currently it supports either
#   single service tag lookup, or bulk via --file argument
#
#-----------------------------------------------------------------------------
require 'optparse' # CLI Option Parser
require 'fileutils' # allow recursive deletion of directory
require 'open-uri' # open URL as a file
require 'pp'

copywrite = "Copyright (c) 2012 Mike Hanby, University of Alabama at Birmingham IT Research Computing."

options = Hash.new # Hash to hold all options parsed from CLI

optparse = OptionParser.new()  do |opts|
  # Help screen banner
  opts.banner = <<EOB
  #{copywrite}
  
  Query the Dell support site for warranty status and model number of a given
  service tag (or list of service tags as provided in --file)

  Usage: #{$0} [options] --src PATH --dest PATH
EOB
  
  # source directory
  options[:svc_tag] = nil
  opts.on('-s', '--svctag SERVICE_TAG', 'Dell Service Tag') do |tag|
    options[:svc_tag] = tag
  end
  
  # hostname
  options[:hostname] = nil
  opts.on('-n', '--host HOSTNAME', 'Host name') do |name|
    options[:hostname] = name
  end
  
  # Bulk option
  options[:file] = nil
  opts.on('-f', '--file FILE', 'Input file, one entry per line HOSTNAME SERVICE_TAG') do |file|
    options[:file] = file
  end
  
  # Output options
  options[:output_fmt] = nil
  opts.on('--format FORMAT', 'Alter default output using one of these formats: tab, csv') do |output_fmt|
    options[:output_fmt] = output_fmt
  end
  
  # Perform batch creation of users from file?
  #options[:debug] = nil
  opts.on('--debug', 'Additional debug output') { |o| options[:debug] = o }
  
  # help
  options[:help] = false
  opts.on('-?', '-h', '--help', 'Display this help screen') do
    puts opts
    exit
  end
end

# parse! removes the processed args from ARGV
optparse.parse!

output_sep = nil # separator used for output, i.e. comma, \t ...

unless options[:output_fmt].nil?
  case options[:output_fmt].downcase
  when "csv"
    output_sep = ","
  when "tab"
    output_sep = "\t"
  else
    raise "Invalid output format specified, see --help for valid options"
  end
end

# Array of hashes to store individual node data
node_list = []

# Raise exceptions for any missing args
if options[:file].nil?
  raise "\nMandatory argument --svctag is missing, see --help for details\n" if options[:svc_tag].nil?
  if options[:hostname].nil?
    options[:hostname] = 'unknown'
  end
  # Set variables
  node_list.push({'hostname' => options[:hostname], 'svc_tag' => options[:svc_tag]})
else
  # Read file contents into array of hashes node_list
  if File.exists?(options[:file])
    f = File.open(options[:file], "r")
    f.each do |line|
      host, tag = line.chomp.split
      node_list.push({'hostname' => host, 'svc_tag' => tag})
    end
    f.close
  end
end

pp node_list if options[:debug]

def dell_query(svc_tag)
  dell_uri = 'http://www.dell.com/support/troubleshooting/us/en/555/Index?servicetag='
  contents = ''
  # Regular Expressions
  regex_model = /<div class="warrantDescription">\s+(.*?)<\/div>/m
  regex_warranty = /<li class="TopTwoWarrantyListItem"><b>\[(.*?)\]<\/b>/m
  open(dell_uri + svc_tag) do |f|
    f.each do |line|
      contents += f.read
  #    puts line if line.match('warrantDescription')
    end
  end

  model = contents.scan(regex_model).to_s.chomp.rstrip
  model.gsub!(/\r\n?/, '')
  a = contents.scan(regex_warranty)
  warranty_exp = contents.scan(regex_warranty)[0].to_s.chomp.rstrip
  warranty_exp.gsub!(/\r\n?/, '')
  return [model, warranty_exp]
end

def print_output(node, index, sep)
  if sep.nil?
    puts "Host: #{node['hostname']}"
    puts "\tModel: #{node['model']}"
    puts "\tService Tag: #{node['svc_tag']}"
    puts "\tWarranty Exp: #{node['warranty_exp']} days left"
  else
    if index == 0 # Print the column headers if this is the first node in the list
      print 'hostname', sep, 'model', sep, 'service_tag', sep, 'warranty_exp_days', "\n"
    end
    print node['hostname'], sep, node['model'], sep, node['svc_tag'], sep, node['warranty_exp'], "\n"
  end
end

node_list.each do |node|
  if node['svc_tag'] == "NA"
    node['model'], node['warranty_exp'], node['svc_tag'] = '<N/A>', '<N/A>', '<N/A>'
  else
    node['model'], node['warranty_exp'] = dell_query(node['svc_tag'])
  end
  
  print_output(node, node_list.index(node), output_sep)
end
