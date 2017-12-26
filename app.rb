require 'sinatra'
require 'net/ssh'
require 'json'
require 'aws-sdk-s3'
require 'mail'
require 'slack-notifier'

configure {
  set :server, :puma
}

get '/' do
  'Kumbaya! The bot is up!'
end

post '/auto' do
  backup

  notifier = Slack::Notifier.new ENV['WEBHOOK_URL'] do
    defaults channel: ENV['SLACK_CHANNEL'],
              username: ENV['SLACK_USER_NAME']
  end

  notifier.ping "Guys, I sent the email with backup urls to you guys. Enjoy and good night!"

  respond_message "Huray! The backup files is generated! Check your inbox pls!"
end

post '/backup' do
  backup

  respond_message "Huray! The backup files is generated! Check your inbox pls!"
end

def backup
  # Execute the command to generate latest backup file
  `PGPASSWORD=$PG_PASSWORD pg_dump -Fc --no-acl --no-owner -h $PG_HOST -p $PG_PORT -U $PG_USER_NAME $PG_DATABASE_NAME > backup/postgres/asiaboxoffice_$(date +%d-%b-%Y-%H-%M-%S).dump`

  # Execute the command to generate latest redis database
  `redis-dump -u $REDIS_URL -d $REDIS_DATABASE > backup/redis/$REDIS_BACKUP_FILE_NAME_$(date +%d-%b-%Y-%H-%M-%S).json`

  # Upload backup files to AWS S3
  postgres_file_name = Dir['backup/postgres/*'].last
  redis_file_name = Dir['backup/redis/*'].last

  s3 = Aws::S3::Resource.new(region: ENV['AWS_REGION'])

  # postgres file
  postgres_obj = s3.bucket(ENV['AWS_BUCKET']).object(postgres_file_name)
  postgres_obj.upload_file("#{postgres_file_name}")
  postgres_backup_url = obj.presigned_url(:get, expires_in: 60 * 60)

  # redis file
  redis_obj = s3.bucket(ENV['AWS_BUCKET']).object(redis_file_name)
  redis_obj.upload_file("#{redis_file_name}")
  redis_backup_url = obj.presigned_url(:get, expires_in: 60 * 60)

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
        Yoh!

        Download the postgres file at here: #{postgres_backup_url} - and the redis file at here: #{redis_backup_url}.

        These link only available in 60 minutes.

        Enjoy."
    end
  end
end

def respond_message message
  content_type :json
  {:text => message}.to_json
end
