require 'sinatra'
require 'net/ssh'
require 'json'
require 'aws-sdk-s3'
require 'byebug'

configure {
  set :server, :puma
}

get '/' do
  'Kumbaya! The bot is up!'
end

post '/hello' do
  respond_message 'Morning @vincent! Time to backup database'
end

post '/backup' do
  # Execute the command
  `PGPASSWORD=$PG_PASSWORD pg_dump -Fc --no-acl --no-owner -h $PG_HOST -p $PG_PORT -U $PG_USER_NAME $PG_DATABASE_NAME > backup/asiaboxoffice_$(date +%d-%b-%Y).dump`
  file_name = Dir['backup/*'].last

  s3 = Aws::S3::Resource.new(region: ENV['AWS_REGION'])
  obj = s3.bucket(ENV['AWS_BUCKET']).object(file_name)
  obj.upload_file("#{file_name}")
  obj.presigned_url(:get, expires_in: 60 * 60)

  respond_message "Huray! The backup file is generated! Check your inbox pls!"
end

def respond_message message
  content_type :json
  {:text => message}.to_json
end
