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
  now = Time.now.strftime("%d-%b-%Y-%H-%M-%S-%z")

  zip_backup_url = backup(now)

  send_mail(zip_backup_url, now)

  notifier = Slack::Notifier.new ENV['WEBHOOK_URL'] do
    defaults channel: ENV['SLACK_CHANNEL'],
              username: ENV['SLACK_USER_NAME']
  end

  notifier.ping "Good morning! Have a nice day!"
end

post '/hourly-run' do
  now = Time.now.strftime("%d-%b-%Y-%H-%M-%S-%z")
  backup(now)
end

post '/run-backup' do
  now = Time.now.strftime("%d-%b-%Y-%H-%M-%S-%z")
  send_to_slack(now)
end

post '/new-backup' do
  now = Time.now.strftime("%d-%b-%Y-%H-%M-%S-%z")
  if params[:app] == ENV["APP_1"]
    new_backup(now, ENV['PG_PASSWORD'], ENV['PG_HOST'], ENV['PG_PORT'], ENV['PG_DATABASE_NAME'], ENV['PG_USER_NAME'], ENV['REDIS_URL'], ENV['REDIS_DATABASE'], ENV['APP_1'])
  elsif params[:app] == ENV["APP_2"]
    new_backup(now, ENV['PG_PASSWORD_2'], ENV['PG_HOST_2'], ENV['PG_PORT_2'], ENV['PG_DATABASE_NAME_2'], ENV['PG_USER_NAME_2'], ENV['REDIS_URL_2'], ENV['REDIS_DATABASE_2'], ENV['APP_2'])
  end
  'DONE'
end

def send_to_slack(now)
  bitly_link = generate_short_link(backup(now))

  notifier = Slack::Notifier.new ENV['WEBHOOK_URL'] do
    defaults channel: ENV['SLACK_CHANNEL'],
              username: ENV['SLACK_USER_NAME']
  end

  notifier.ping "The backup database at #{now} is here: #{bitly_link}"
end

def new_backup(now, pg_password, pg_host, pg_port, pg_database_name, pg_user_name, redis_url, redis_database, project_name)
  # Execute the command to generate latest backup file
  `PGPASSWORD=#{pg_password} pg_dump -Fc --no-acl --no-owner -h #{pg_host} -p #{pg_port} -U #{pg_user_name} #{pg_database_name} > backup/postgres/#{project_name}_postgres_$(date +%d-%b-%Y-%H-%M-%S).dump`

  # Execute the command to generate latest redis database
  `redis-dump -u #{redis_url} -d #{redis_database} > backup/redis/#{project_name}_redis_$(date +%d-%b-%Y-%H-%M-%S).json`

  # Zip backup files
  postgres_file_path = Dir["backup/postgres/#{project_name}_postgres_*.dump"].sort_by{ |f| File.mtime(f) }.last
  redis_file_path = Dir["backup/redis/#{project_name}_redis_*.json"].sort_by{ |f| File.mtime(f) }.last

  zip_file_path = "backup/#{project_name}-backup-#{now}.zip"

  Zip::File.open(zip_file_path, Zip::File::CREATE) do |zipfile|
    zipfile.add(postgres_file_path.split("/").last, postgres_file_path)
    zipfile.add(redis_file_path.split("/").last, redis_file_path)
  end

  # GPG encrypt the zip file
  `gpg --encrypt --recipient $YOUR_RECIPIENT #{zip_file_path}`

  new_zip_file_path = zip_file_path + ".gpg"

  # Upload zip file to S3
  s3 = Aws::S3::Resource.new(region: ENV['AWS_REGION'])

  zip_obj = s3.bucket(ENV['AWS_BUCKET']).object(new_zip_file_path)
  zip_obj.upload_file("#{new_zip_file_path}")
  zip_obj.presigned_url(:get, expires_in: 60 * 60)
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

  # GPG encrypt the zip file
  `gpg --encrypt --recipient $YOUR_RECIPIENT #{zip_file_path}`

  new_zip_file_path = zip_file_path + ".gpg"

  # Upload zip file to S3
  s3 = Aws::S3::Resource.new(region: ENV['AWS_REGION'])

  zip_obj = s3.bucket(ENV['AWS_BUCKET']).object(new_zip_file_path)
  zip_obj.upload_file("#{new_zip_file_path}")
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
