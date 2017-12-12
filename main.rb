require 'rubygems'
require 'net/ssh'
require 'optparse'

opts = OptionParser.new

opts.on("-h HOSTNAME", "--hostname NAME", String, "Hostname of Server") { |v| @hostname = v }
opts.on("-u SSH USERNAME", "--username SSH USERNAME", String, "SSH Username of Server") { |v| @username = v }
opts.on("-p SSH PASSWORD", "--password SSH PASSWORD", String, "SSH Password of Server") { |v| @password = v }
opts.on("-c SHELL_COMMAND", "--command SHELL_COMMAND", String, "Shell Command to Execute") { |v| @cmd = v }

begin
  opts.parse!(ARGV)
rescue OptionParser::ParseError => e
  puts e
end

raise OptionParser::MissingArgument, "Hostname [-h]" if @hostname.nil?
raise OptionParser::MissingArgument, "SSH Username [-u]" if @username.nil?
raise OptionParser::MissingArgument, "SSH Password [-p]" if @password.nil?
raise OptionParser::MissingArgument, "Command to Execute [-c]" if @cmd.nil?

begin
  result = ''

  # Start SSH connection
  Net::SSH.start(@hostname, @username, :password => @password) do |ssh|

    # Open a channel
    channel = ssh.open_channel do |channel, success|
      channel.on_data do |channel, data|
        if data =~ /^\[sudo\] password for /
          channel.send_data "#{@password}\n"
        else
          result += data.to_s
        end
      end

      # Request a pseudo TTY
      channel.request_pty

      # Execute the command
      channel.exec(@cmd)

      # Wait for response
      channel.wait
    end

    # Wait for opened channel
    channel.wait
  end

  puts "Huray! The backup file is generated! Next I'll send to you guys via email"
rescue
  puts "Unable to connect to #{@hostname} using #{@username}/#{@password}"
end
