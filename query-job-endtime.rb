#!/usr/bin/env ruby
#-----------------------------------------------------------------------------
# Name        :  query-job-endtime.rb
# Author      :  Mike Hanby < mhanby at uab.edu >
# Organization:  University of Alabama at Birmingham IT Research Computing
# Description :  This script queries Grid Engine for the end time of a job
#                 
# Usage       :  $0 --jobid 123456
# Date        :  2013-05-14 15:35:00
# Type        :  Query job id and attempt to print in human form the absolute end
#                time of the job based on the hard runtime request (h_rt)
# qstat -j 9130603 -r | grep h_rt | awk '{print $3}' | cut -d , -f 1 | cut -d = -f 2
#
# I at first thought I could obtain all of the information needed from the
# "qstat -j JOB_ID" command. Unfortunately, SGE doesn't provide the Start Time
# in the output. Unfortunately this means the script needs to run the qstat command
# multiple times to gather the needed information.
# 
# Array jobs add another complexity. As a result, all queries will output an array
# whether the job has 1 task (non array job), or multiple
#-----------------------------------------------------------------------------
# History
# 20130617 - mhanby - v1.1.1
#   - Code no longer crashes when querying a jobid or userid that do not match to running
#     jobs
#   - Fixed a bug in the new --userid code that resulted in the same job id being added
#     to the jobid array if an SGE Array job was in the mix.
#   - Added code to remove duplicate job id's or user id's submitted on the command line
#   - Fixed a crash that would happen if --userid only had a single running job. In the
#     XML from qstat, joblist is an array if there are multiple jobs, if a single job, it's
#     just a hash for the one job
# 20130522 - mhanby - v1.1.0
#   - Modified code to move methods into new class called Job to support multiple job
#     objects
#   - Added new option to display job end times for specific users
#   - Better report layout
# 20130514 - mhanby - v1.0.0
#   - Initial creation of script - Currently displays running tasks plus endtimes
#   - Currently no error handling for a non existent job (i.e. job that is no longer running)
#
# TODO: more output options (csv, tab delim, XML, PDF)
# TODO: error handling
# TODO: query for all running jobs
# DONE: query for specific user

# SGE env variables that should already be loaded in the users env
  # SGE_CELL=default
  # SGE_ARCH=lx26-amd64
  # SGE_EXECD_PORT=537
  # SGE_QMASTER_PORT=536
  # SGE_ROOT=/opt/gridengine
  # LD_LIBRARY_PATH /opt/gridengine/lib/lx26-amd64
  # PATH /opt/gridengine/bin/lx26-amd64
  # sge_cell = ENV['SGE_CELL']
  # sge_arch = ENV['SGE_ARCH']
  # sge_execd_port = ENV['SGE_EXECD_PORT']
  # sge_qmaster_port = ENV['SGE_QMASTER_PORT']
  # sge_root = ENV['SGE_ROOT']
  # path = ENV['PATH']
  # ld_library_path = ENV['LD_LIBRARY_PATH']

##############################
# Note on installing gems in your $HOME
# First, add the following to your ~/.bashrc file:
# # Ruby
# export RUBYVER=`ruby --version | cut -d" " -f 2 | cut -d. -f 1,2`
# export GEM_HOME=$HOME/.ruby/lib/ruby/gems/${RUBYVER}
# export RUBYLIB=$HOME/.ruby/lib/ruby:$HOME/.ruby/lib/site_ruby/${RUBYVER}:$RUBYLIB
#
# Next either exit and log back in, or run the same commands above in your shell
#
# Then create the GEM_HOME directory:
#
# mkdir -p $GEM_HOME
#
# Now install:
#
# gem install crack
##############################
require 'rubygems' 
require 'optparse' # CLI Option Parser
require 'crack'    # For XML to Hash # gem install crack -s http://gems.github.com
require 'time'     # For time calculation

@@VERSION = '1.1.1'
copywrite = 'Copyright (c) 2013 Mike Hanby, University of Alabama at Birmingham IT Research Computing.'
appname = 'Grid Engine'

options = Hash.new # Hash to hold options parsed from CLI

optparse = OptionParser.new()  do |opts|
  # Help screen banner
  opts.banner = <<EOF
  #{copywrite}
  
  #{File.basename("#{$0}")} - version #{@@VERSION}

  Query #{appname} by job id and attempt to print, in human
  form, the absolute end time of the job based on the hard
  runtime request (h_rt)

EOF
  
  # Grid Engine Job IDs
  options[:jobid] = nil
  opts.on('-j', '--jobid 12345', Array,
          "Comma separated list of #{appname} JobID's to query") { |o| options[:jobid] = o }
  # Grid Engine User Names
  options[:userid] = nil
  opts.on('-u', '--userid jsmith', Array,
          "Comma separated list of #{appname} UserID's to query") { |o| options[:userid] = o }
  # debug
  options[:debug] = false
  opts.on('--debug',
          'Display additional output like internal structures') { |o| options[:debug] = o }
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

if options[:debug]
  debug = options[:debug]
  require 'pp'
end

jobid = Array.new
if options[:jobid]
  jobid = options[:jobid]
  # Remove any duplicate job id's
  jobid = jobid.uniq
#else
#  # Prompt user for input if not specified on command line:
#  loop do
#    print "Job ID to query: "
#    id = gets.chomp
#
#    if id.empty?
#      puts "No input!"
#    elsif id.index(/\d+/)
#      jobid = id
#      break
#    end
#  end
end

userid = Array.new
if options[:userid]
  userid = options[:userid]
  # Remove any duplicate user id's
  userid = userid.uniq
end

# Begin Job class
class Job
  def initialize(jobid, debug)
    @jobid = jobid
    @debug = debug
    @outxml = query_job_metadata
    @valid_id = true
    
    # How do we prevent the object from being created if the given JobID doesn't exist?
    #next unless @outxml.include?("unknown_jobs") # JobID doesn't exist
    if @outxml.include?("unknown_jobs")
      @valid_id = false 
    else
      pp @outxml if @debug
      # convert the xml into a hash
      @jobinfo = Hash.new
      @jobinfo = Crack::XML.parse(@outxml)
      pp @jobinfo if @debug
      
      # Get the owner from the hash
      @owner = @jobinfo["detailed_job_info"]["djob_info"]["element"]["JB_owner"]
      
      # Get maximum runtime in seconds for the job based on the h_rt resource request
      # The value is stored in an array of hashes under qstat_l_requests along with any other resource reqeust
      @max_runtime = ''
      @jobinfo["detailed_job_info"]["djob_info"]["element"]["JB_hard_resource_list"]["qstat_l_requests"].each do |x|
        @max_runtime = x["CE_stringval"] if x["CE_name"] == "h_rt"
      end
      
      # Create the array of running tasks
      @tasks = Array.new
      @tasks = running_tasks
      @tasks.each do |task|
      #  puts task["taskid"]
        # Calculate the end time and store it with the task
        t1 = Time.parse("#{task['start_date']} #{task['start_time']}") 
        endtime = t1 + @max_runtime.to_i
        puts endtime if debug
        task["end_time"] = endtime.strftime("%Y/%m/%d %H:%M:%S") # format end_time to make it more compact
      end      
    end
  end # End initialize()
  
  # method to query whether or not the jobid is valid
  def valid?
    @valid_id 
  end
  
  # method to return jobID
  def jobid?
    @jobid
  end
  
  # Query a jobid and store results in a hash
  def query_job_metadata
    outxml = ''
    IO.popen("qstat -j #{@jobid} -xml").each do |line|
      outxml << line.chomp
    end
    outxml
  end # end query_job_metadata()
  
  # return list of running tasks for job
  def running_tasks
    out = Array.new
    tasklist = Array.new
    IO.popen("qstat -u #{@owner} -s r | grep #{@jobid} ").each do |line|
      out << line.chomp
    end
    out.each do |x|
      task = x.split()
      tasklist << {
        'jobid' => task[0],
        'prior' => task[1],
        'name' => task[2],
        'user' => task[3],
        'status' => task[4],
        'start_date' => task[5],
        'start_time' => task[6],
        'queue' => task[7],
        'slots' => task[8],
        'taskid' => task[9],
      }
      # Set the taskid to 0 for non array jobs, otherwise taskid will be unset
      unless tasklist[0]['taskid']
        tasklist[0]['taskid'] = 0
      end
    end
    tasklist
  end # end running_tasks()
  
  # print friendly time given number of seconds
  # Taken from http://stackoverflow.com/questions/2310197/how-to-convert-270921sec-into-days-hours-minutes-sec-ruby
  def seconds_to_units(seconds)
    #'%d days, %d hours, %d mins, %d secs' %
    #'%d:%d:%d:%d' %
    '%d Days %d Hours %d Mins %d Secs' %
      # the .reverse lets us put the larger units first for readability
      [24,60,60].reverse.inject([seconds]) {|result, unitsize|
        result[0,0] = result.shift.divmod(unitsize)
        result
      }
  end # end seconds_to_units

  # print in table format
  def print_table
    runtime = seconds_to_units(@max_runtime.to_i)
    #puts "=" * 50
    #puts "  JobID: #{@jobid} - Owner: #{@owner}"
    #puts "  Max Runtime: #{seconds_to_units(@max_runtime.to_i)}"
    @tasks.each do |task|
      printf "%-13s %-8s %-15s %-22s %s\n", @jobid, task['taskid'], @owner, task['end_time'], runtime
    end
  end
  def print
    # Print report
    runtime = ''
    #puts "=" * 50
    puts "  JobID: #{@jobid} - Owner: #{@owner}"
    puts "  Max Runtime: #{seconds_to_units(@max_runtime.to_i)}"
    puts ""
    puts "  TaskID\tMaxEndTime"
    puts "  " + "-" * 50
    @tasks.each do |task|
      puts "  #{task['taskid']}\t#{task['end_time']}"
    end
    puts "=" * 50
  end

end # End Job class

userid.each do |user|
  # list jobs running under the user account and add the job id to the jobid array
  puts user if debug
  outxml = ''
  IO.popen("qstat -u #{user} -s r -xml").each do |line|
    outxml << line.chomp
  end
  puts outxml if debug
  #next if outxml.split("\n").grep(/unknown_jobs/)
  next unless outxml.include?("JB_job_number") # user doesn't have any jobs
  userinfo = Hash.new
  userinfo = Crack::XML.parse(outxml)
  pp userinfo if debug
  # In the XML from qstat, joblist is an array if there are multiple jobs, if a single job, it's
  # just a hash for the one job
  if userinfo["job_info"]["queue_info"]["job_list"].kind_of?(Array)
    userinfo["job_info"]["queue_info"]["job_list"].each do |job|
      puts job["JB_job_number"] if debug
      # Be sure to only add the id if it's unique. Array jobs will result in multiple
      # occurances of the same job id
      jobid << job["JB_job_number"] unless jobid.include?(job["JB_job_number"])
    end
  else
    job = userinfo["job_info"]["queue_info"]["job_list"]["JB_job_number"]
    puts job if debug
    jobid << job unless jobid.include?(job)
  end
end

jobs = Array.new
jobid.each do |id|
  jobs << Job.new(id, debug)
end

# Print the header
#     9186455         0          johndoe         2013/06/20 20:19:55
puts 'JobID         TaskID   Owner           Max End Time           Requested Run Time'
puts '============  =======  ==============  =====================  =============================='

jobs.each do |job|
  if job.valid?
    job.print_table
  else
    puts "#{job.jobid?} is either invalid or not running"
  end
end