require 'rake'

namespace :setup do
  desc 'プロジェクトの初期設定'
  task :init do
    puts "MT4 Backtester プロジェクトを初期化しています..."
    # 初期化ロジック
  end
end

namespace :backtest do
  desc 'バックテストを実行'
  task :run, [:strategy, :start_date, :end_date] do |t, args|
    puts "バックテストを実行しています..."
    puts "戦略: #{args[:strategy]}"
    puts "期間: #{args[:start_date]} から #{args[:end_date]}"
    # バックテスト実行ロジック
  end
end