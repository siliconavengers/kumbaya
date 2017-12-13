require 'sinatra'
require 'net/ssh'
require 'json'
require 'aws-sdk-s3'
require 'mail'

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
  # Execute the command to generate latest backup file
  `PGPASSWORD=$PG_PASSWORD pg_dump -Fc --no-acl --no-owner -h $PG_HOST -p $PG_PORT -U $PG_USER_NAME $PG_DATABASE_NAME > backup/asiaboxoffice_$(date +%d-%b-%Y-%H-%M-%S).dump`

  # Upload backup file to AWS S3
  file_name = Dir['backup/*'].last

  s3 = Aws::S3::Resource.new(region: ENV['AWS_REGION'])
  obj = s3.bucket(ENV['AWS_BUCKET']).object(file_name)
  obj.upload_file("#{file_name}")
  backup_url = obj.presigned_url(:get, expires_in: 60 * 60)

  # Sending email - Use DirectMail server of Alicloud for now
  Mail.defaults do
    delivery_method :smtp, {
      :port      => ENV['MAIL_PORT'],
      :address   => ENV['MAIL_ADDRESS'],
      :user_name => ENV['MAIL_USER_NAME'],
      :password  => ENV['MAIL_PASSWORD'],
      :enable_starttls_auto => false,
      :openssl_verify_mode => 'none',
    }
  end

  mail = Mail.deliver do
    to      ENV['MAIL_TO']
    from    ENV['MAIL_FROM']
    subject 'New backup database file from AsiaboxOffice'
    text_part do
      body "
        Yoh! Download the file at here: #{backup_url}. This link only available in 60 minutes.

        Check this link: https://devcenter.heroku.com/articles/heroku-postgres-import-export#restore-to-local-database to know how to restore to your local database.

        Enjoy."
    end
  end

  respond_message "Huray! The backup file is generated! Check your inbox pls!"
end

def respond_message message
  content_type :json
  {:text => message}.to_json
end
