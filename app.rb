require 'sinatra'
require 'net/ssh'
require 'json'

get '/' do
  'Kumbaya! The bot is up!'
end

post '/backup' do
  # Execute the command
  command = "PGPASSWORD=#{ENV['PG_PASSWORD']} pg_dump -Fc --no-acl --no-owner -h #{ENV['PG_HOST']} -p #{ENV['PG_PORT']} -U #{ENV['PG_USER_NAME']} #{ENV['PG_DATABASE_NAME']} > asiaboxoffice_#{Time.now}.dump"
  exec(command)

  respond_message "Huray! The backup file is generated!"
end

post '/backup_from_local' do
  result = ''

  # Start SSH connection
  Net::SSH.start(ENV['SSH_HOST_NAME'], ENV['SSH_USER_NAME]'], :password => ENV['SSH_PASSWORD']) do |ssh|

    # Open a channel
    channel = ssh.open_channel do |channel, success|
      channel.on_data do |channel, data|
        if data =~ /^\[sudo\] password for /
          channel.send_data "#{ENV['SSH_PASSWORD']}\n"
        else
          result += data.to_s
        end
      end

      # Request a pseudo TTY
      channel.request_pty

      # Execute the command
      command = "PGPASSWORD=#{ENV['PG_PASSWORD']} pg_dump -Fc --no-acl --no-owner -h #{ENV['PG_HOST']} -p #{ENV['PG_PORT']} -U #{ENV['PG_USER_NAME']} #{ENV['PG_DATABASE_NAME']} > asiaboxoffice_#{Time.now}.dump"
      channel.exec(command)

      # Wait for response
      channel.wait
    end

    # Wait for opened channel
    channel.wait
  end

  respond_message "Huray! The backup file is generated!"
end

def respond_message message
  content_type :json
  {:text => message}.to_json
end
