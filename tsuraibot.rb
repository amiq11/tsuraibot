#!/usr/bin/env ruby
# coding: utf-8

require 'rubygems'
require 'net/https'
require 'twitter'
require 'oauth'
require 'json'
require 'pp'
require 'thread'
require './twauth'

class TsuraiBot
   CONSUMER_KEY       = "YourKey"
   CONSUMER_SECRET    = "YourSecretKey"

  #botのTwitterID
  MY_SCREEN_NAME = "tsuraibot"
  #ここは気にしなくてよい。USER_AGENTを与えておかないと公式に怒られます。
  BOT_USER_AGENT = "tsuraibot @#{MY_SCREEN_NAME}"
  #証明書のパスを指定します。これも同じ階層にアップロードすること。
  HTTPS_CA_FILE_PATH = "./tsuraibot.cer"
  # データ保存先ファイル名 -- sqlite3で保存
  DBFILENAME = "tsuraibot.dat"

  def initialize
    @auth = TWAuth.new( CONSUMER_KEY, CONSUMER_SECRET, DBFILENAME )
    @tsuraiq = Queue.new
    @dbfile = DBFILENAME
  end

  def run
    t_stream = Thread.new { stream }
    t_twit = Thread.new {
      loop do
        sleep 30*60
        begin
          t = get_db_randomly "tsurai"
          post t[0][0]
        rescue
          puts "#{$!}"
        end
      end
    }
    t_flush = Thread.new {
      loop do
        puts "flush"
        STDOUT.oflush
        STDOUT.flush
        sleep 60
      end
    }
    t_stream.join
    t_twit.kill
    t_flush.kill
  end

  private
  def stream
    count = 0
    begin
      # jsonがパースされたものがブロック引数に来る
      connect do |msg|
        #           pp msg
        print_post msg
        find_save msg
        refollow msg
      end
    rescue Timeout::Error, StandardError
      puts "Error!!: #{$!}"
      sleep 1
      retry
    end
  end

  def find_save msg
    if msg['user']
      if msg['user']['screen_name'] != MY_SCREEN_NAME
        find( "つらい", msg )     { |m| save_twit( "tsurai", m )   if !( /^RT @#{MY_SCREEN_NAME}/ =~ m['text'] ) } or
          find( "つらみ", msg )     { |m| save_twit( "tsurai", m ) if !( /^RT @#{MY_SCREEN_NAME}/ =~ m['text'] ) } or
          find( "しにたみ", msg )   { |m| save_twit( "tsurai", m ) if !( /^RT @#{MY_SCREEN_NAME}/ =~ m['text'] ) } or
          find( "死にたみ", msg )   { |m| save_twit( "tsurai", m ) if !( /^RT @#{MY_SCREEN_NAME}/ =~ m['text'] ) } or
          find( "ﾀﾉﾁｰ", msg )      { |m| save_twit( "tsurai", m )  if !( /^RT @#{MY_SCREEN_NAME}/ =~ m['text'] ) } or
          find( "タノチー", msg )   { |m| save_twit( "tsurai", m ) if !( /^RT @#{MY_SCREEN_NAME}/ =~ m['text'] ) } or
          find( "たのちー", msg )   { |m| save_twit( "tsurai", m ) if !( /^RT @#{MY_SCREEN_NAME}/ =~ m['text'] ) }
      end
    end
  end
  def find text, msg
    if msg['text']
      if msg['text'].include?( text )
        yield msg
        return true
      end
    end
    false
  end


  def connect
    uri = URI.parse("https://userstream.twitter.com/2/user.json?track=#{MY_SCREEN_NAME}")

    https = Net::HTTP.new(uri.host, uri.port)
    https.use_ssl = true
    https.ca_file = HTTPS_CA_FILE_PATH
    https.verify_mode = OpenSSL::SSL::VERIFY_PEER
    https.verify_depth = 5

    pp https

    https.start do |https|
      request = Net::HTTP::Get.new(uri.request_uri)
      request["User-Agent"] = BOT_USER_AGENT
      request.oauth!(https, @auth.consumer, @auth.token)

      buf = ""
      https.request(request) do |response|
        response.read_body do |chunk|
          buf << chunk
          # jsonのパース
          while(line = buf[/.+?(\r\n)+/m]) != nil
            begin
              buf.sub!(line,"")
              line.strip!
              status = JSON.parse(line)
            rescue
              break
            end
            yield status
          end
        end
      end
    end
  end

  def refollow msg
    if msg['event'] == "follow"
      puts "follow: #{msg['source']['screen_name']}(#{msg['source']['id']}) => #{msg['target']['screen_name']}(#{msg['target']['id']})"
      if msg['target']['screen_name'] == MY_SCREEN_NAME
        ret = @auth.token.post( '/1.1/friendships/create.json',
                         'user_id' => msg['source']['id'],
                         'follow'  => true
                         )
        if ret.class != Net::HTTPOK
          puts "refollow is failed: #{ret}"
        end
      end
    end
  end

  def post text, option={}
    param={}
    param[ :status ] = text
    param[ :in_reply_to_status_id ] = option[ :reply_id ] if option[ :reply_id ]
    ret = @auth.token.post('/1.1/statuses/update.json', param )
    if ret.class != Net::HTTPOK
      puts "Post ( #{text} ) is failed: #{ret}"
    else
      puts "success update! :: #{text}"
    end
  end

  def print_post msg
    if msg['text']        # tweet
      puts "#{"%20s"%msg['user']['name']} -- #{"%15s"%msg['user']['screen_name']} : #{msg['text']}"
    end
  end

  def save_twit table, msg
    begin
      puts "open #{table}"
      db = SQLite3::Database.new( @dbfile )
      db.execute( "INSERT INTO #{table} ( twitid, text, name, screen_name, date ) VALUES ( ?,?,?,?,? );",
                 msg['id'], msg['text'], msg['user']['name'], msg['user']['screen_name'], msg['created_at'] )
      db.close
      puts "saved: ( #{msg['id']}, '#{msg['text']}', '#{msg['user']['name']}', '#{msg['user']['screen_name']}', '#{msg['created_at']}' )"
    rescue SQLite3::SQLException
      puts "Error in 'save_twit': #{$!}"
      puts "table: #{table} will create"
      db.execute( "
CREATE TABLE #{table} (
    id          integer PRIMARY KEY AUTOINCREMENT,
    twitid      integer,
    text        text,
    name        text,
    screen_name text,
    date        text
);")
      retry
    end
  end

  def get_db_randomly table
    begin
      db = SQLite3::Database.new( @dbfile )
#       twit = db.execute( "SELECT text, name, screen_name FROM #{table} ORDER BY RANDOM() LIMIT 1;" )
      twit = db.execute( "SELECT text, name, screen_name FROM #{table} as tbl, ( SELECT id FROM tsurai ORDER BY RANDOM() LIMIT 1 ) AS random WHERE tbl.id == random.id;" ) # こっちのほうがクエリの取得が早いみたい。
      db.close
      twit
    rescue
      puts "Error in 'get_db_randomly': #{$!}"
      raise "There is no data"
    end
  end
end

if $0 == __FILE__
  TsuraiBot.new.run
end
