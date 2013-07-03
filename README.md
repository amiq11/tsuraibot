tsuraibot
=========

世の中のつらいを代弁するbotのソース


* 概要
 sqliteの使い方、およびOAuthでの認証の仕方の練習を兼ねて作ったbotです。
* 使い方
 * 環境
  - 前提
   - ruby1.9.3がインストール済み
  - インストール
   以下のコマンドを打てばいいはず。
    gem install twitter oauth json sqlite3
   各自、CONSUMER_KEY / CONSUMER_SECRETを取得する必要があります。 // rubyでうまく埋める方法がわからなかった  
   これについてはググるとすぐに出てくると思うので頑張ってください。
 * 実行
  - 以下のコマンドだけで動作します。
    ./tsuraibot.rb
   ssh越しに、サーバ上でバックグラウンドで動作させたい場合は以下のようにしてみてください。
    nohup ./tsuraibot.rb &
* ソースツリー
 - twauth.rb
  twitterのoauthでaccess_tokenを簡単に得ることができ、それを保存出来るようにしてみました。
 - tsuraibot.rb
  userstreamからpostを取得し、つらいものを抜き取ってsqliteで保存してみました。
