require 'sinatra'
require 'net/ssh'
require 'json'
require 'aws-sdk-s3'
require 'mail'
require 'slack-notifier'
require 'zip'

configure {
  set :server, :puma }

get '/' do
  'Kumbaya! The bot is up!'
end

post '/auto' do
  backup

  notifier = Slack::Notifier.new ENV['WEBHOOK_URL'] do
    defaults channel: ENV['SLACK_CHANNEL'],
              username: ENV['SLACK_USER_NAME']
  end

  notifier.ping "Guys, I sent the email with backup url. Enjoy and good night!"

  respond_message "Huray! Two backup files for postgres and redis are generated! Check your inbox pls!"
end

post '/backup' do
  backup

  notifier = Slack::Notifier.new ENV['WEBHOOK_URL'] do
    defaults channel: ENV['SLACK_CHANNEL'],
              username: ENV['SLACK_USER_NAME']
  end

  notifier.ping "Yoh! I sent the backup files. Check your email pls!"
end

def backup
  # Execute the command to generate latest backup file
  `PGPASSWORD=$PG_PASSWORD pg_dump -Fc --no-acl --no-owner -h $PG_HOST -p $PG_PORT -U $PG_USER_NAME $PG_DATABASE_NAME > backup/postgres/postgres_$(date +%d-%b-%Y-%H-%M-%S).dump`

  # Execute the command to generate latest redis database
  `redis-dump -u $REDIS_URL -d $REDIS_DATABASE > backup/redis/redis_$(date +%d-%b-%Y-%H-%M-%S).json`

  # Zip backup files
  postgres_file_path = Dir['backup/postgres/*'].sort_by{ |f| File.mtime(f) }.last
  redis_file_path = Dir['backup/redis/*'].sort_by{ |f| File.mtime(f) }.last

  now = Time.now

  zip_file_path = "backup/data-backup-#{now}.zip"

  Zip::File.open(zip_file_path, Zip::File::CREATE) do |zipfile|
    zipfile.add(postgres_file_path.split("/").last, postgres_file_path)
    zipfile.add(redis_file_path.split("/").last, redis_file_path)
  end

  # Upload zip file to S3
  s3 = Aws::S3::Resource.new(region: ENV['AWS_REGION'])

  zip_obj = s3.bucket(ENV['AWS_BUCKET']).object(zip_file_path)
  zip_obj.upload_file("#{zip_file_path}")
  zip_backup_url = zip_obj.presigned_url(:get, expires_in: 60 * 60)

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
    subject "New backup database file for AsiaBoxOffice at #{now}"
    text_part do
      body "
        Yoh!

        Download the backup file at here: #{zip_backup_url}.

        This link only available in 60 minutes.

        Enjoy."
    end
  end
end

def respond_message message
  content_type :json
  {:text => message}.to_json
end
