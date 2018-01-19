require 'sinatra'
require 'net/ssh'
require 'json'
require 'aws-sdk-s3'
require 'mail'
require 'slack-notifier'
require 'zip'
require 'bitly'

configure { set :server, :puma }

get '/' do
  'Kumbaya! The bot is up!'
end

post '/auto' do
  now = Time.now

  zip_backup_url = backup(now)

  send_mail(zip_backup_url, now)

  notifier = Slack::Notifier.new ENV['WEBHOOK_URL'] do
    defaults channel: ENV['SLACK_CHANNEL'],
              username: ENV['SLACK_USER_NAME']
  end

  notifier.ping "Morning! I sent an email with backup database. Thanks! Have a nice day!"
end

post '/auto-hour' do
  backup(now)
end

post '/backup' do
  now = Time.now

  bitly_link = generate_short_link(backup(now))

  notifier = Slack::Notifier.new ENV['WEBHOOK_URL'] do
    defaults channel: ENV['SLACK_CHANNEL'],
              username: ENV['SLACK_USER_NAME']
  end

  notifier.ping "Done! The backup file for #{now} is here: #{bitly_link}"
end

def backup(now)
  # Execute the command to generate latest backup file
  `PGPASSWORD=$PG_PASSWORD pg_dump -Fc --no-acl --no-owner -h $PG_HOST -p $PG_PORT -U $PG_USER_NAME $PG_DATABASE_NAME > backup/postgres/postgres_$(date +%d-%b-%Y-%H-%M-%S).dump`

  # Execute the command to generate latest redis database
  `redis-dump -u $REDIS_URL -d $REDIS_DATABASE > backup/redis/redis_$(date +%d-%b-%Y-%H-%M-%S).json`

  # Zip backup files
  postgres_file_path = Dir['backup/postgres/*'].sort_by{ |f| File.mtime(f) }.last
  redis_file_path = Dir['backup/redis/*'].sort_by{ |f| File.mtime(f) }.last

  zip_file_path = "backup/data-backup-#{now}.zip"

  Zip::File.open(zip_file_path, Zip::File::CREATE) do |zipfile|
    zipfile.add(postgres_file_path.split("/").last, postgres_file_path)
    zipfile.add(redis_file_path.split("/").last, redis_file_path)
  end

  # Upload zip file to S3
  s3 = Aws::S3::Resource.new(region: ENV['AWS_REGION'])

  zip_obj = s3.bucket(ENV['AWS_BUCKET']).object(zip_file_path)
  zip_obj.upload_file("#{zip_file_path}")
  zip_obj.presigned_url(:get, expires_in: 60 * 60)
end

def send_mail(zip_backup_url, now)
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

  short_link = generate_short_link(zip_backup_url)

  mail = Mail.deliver do
    to      ENV['MAIL_TO']
    from    ENV['MAIL_FROM']
    subject "New backup database file for AsiaBoxOffice at #{now}"
    text_part do
      body "
        Yoh!

        Download the backup file at here: #{short_link}.

        This link only available in 60 minutes.

        Enjoy."
    end
  end
end

def generate_short_link(zip_backup_url)
  Bitly.use_api_version_3
  bitly = Bitly.new(ENV['BITLY_USER_NAME'], ENV['BITLY_API_KEY'])
  bitly_link = bitly.shorten(zip_backup_url)
  bitly_link.short_url
end
