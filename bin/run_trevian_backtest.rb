#!/usr/bin/env ruby

require 'optparse'
require_relative '../lib/mt4_backtester'
# 環境変数から設定を読み込む
params = MT4Backtester::Config::ConfigLoader.load
# コマンドラインオプションのパース
options = {
  mq4_file: 'data/trevian_ZA701.mq4',
  data_file: nil,
  start_date: nil,
  end_date: nil,
  output_file: nil,
  symbol: 'GBPUSD',
  timeframe: 'M1',
  gap: params[:Gap],
  takeprofit: params[:Takeprofit],
  start_lots: params[:Start_Lots]
}

OptionParser.new do |opts|
  opts.banner = "使用法: ruby run_trevian_backtest.rb [options]"
  
  opts.on("-m", "--mq4 FILE", "MT4ファイルのパス") do |file|
    options[:mq4_file] = file
  end
  
  opts.on("-d", "--data FILE", "ティックデータファイルのパス") do |file|
    options[:data_file] = file
  end
  
  opts.on("-s", "--start DATE", "開始日 (YYYY-MM-DD)") do |date|
    options[:start_date] = Time.parse(date)
  end
  
  opts.on("-e", "--end DATE", "終了日 (YYYY-MM-DD)") do |date|
    options[:end_date] = Time.parse(date)
  end
  
  opts.on("-o", "--output FILE", "出力ファイル") do |file|
    options[:output_file] = file
  end
  
  opts.on("-y", "--symbol SYMBOL", "通貨ペア") do |symbol|
    options[:symbol] = symbol
  end
  
  opts.on("-t", "--timeframe TIMEFRAME", "時間枠") do |timeframe|
    options[:timeframe] = timeframe
  end
  
  opts.on("-h", "--help", "ヘルプの表示") do
    puts opts
    exit
  end
end.parse!

puts "Trevianバックテスト実行"
puts "======================="
puts "設定:"
puts "- MT4ファイル: #{options[:mq4_file]}"
puts "- データファイル: #{options[:data_file] || 'サンプルデータを使用'}"
puts "- 期間: #{options[:start_date] ? options[:start_date].strftime('%Y-%m-%d') : '全期間'} から #{options[:end_date] ? options[:end_date].strftime('%Y-%m-%d') : '全期間'}"
puts "- 通貨ペア: #{options[:symbol]}"
puts "- 時間枠: #{options[:timeframe]}"
puts "======================="

# MT4ファイルのパース
puts "\nMT4ファイルを解析中..."
parser = MT4Backtester::Parsers::MT4Parser.new(options[:mq4_file])
strategy_data = parser.parse

puts "EA名: #{strategy_data[:name]}"
puts "パラメータ数: #{strategy_data[:parameters].size}"

# パラメータの変換
params = {}
strategy_data[:parameters].each do |param|
  key = param[:name].to_sym
  value = case param[:type]
           when 'double'
             param[:default_value].to_f
           when 'int', 'long'
             param[:default_value].to_i
           else
             param[:default_value]
           end
  params[key] = value
end

# ティックデータの読み込み
tick_data = []

if options[:data_file]
  puts "\nティックデータを読み込み中..."
  data_loader = MT4Backtester::Data::TickDataFactory.create_loader(
    options[:data_file],
    options[:symbol],
    options[:timeframe].to_sym
  )
  tick_data = data_loader.load(options[:data_file])
  data_loader.print_summary
else
  puts "\nサンプルティックデータを生成中..."
  # サンプルデータ生成
  sample_data_loader = MT4Backtester::Data::CsvTickData.new(options[:symbol], options[:timeframe].to_sym)
  
  # 簡易的なサンプルデータ
  base_time = Time.now - (60 * 60 * 24 * 30)  # 30日前から
  base_price = 1.25  # 基準価格
  
  sample_data = []
  5000.times do |i|
    time = base_time + (i * 60)  # 1分ごと
    
    # ランダムな価格変動を追加
    price_change = rand(-0.001..0.001)
    open = base_price + price_change
    high = open + rand(0..0.0005)
    low = open - rand(0..0.0005)
    close = open + rand(-0.0005..0.0005)
    
    # 次の基準価格を更新
    base_price = close
    
    sample_data << {
      time: time,
      open: open,
      high: high,
      low: low,
      close: close,
      volume: rand(1..100)
    }
  end
  
  tick_data = sample_data
  puts "#{tick_data.size}個のサンプルティックデータを生成しました"
end

# データの期間フィルタリング
if options[:start_date] || options[:end_date]
  original_size = tick_data.size
  
  if options[:start_date]
    tick_data = tick_data.select { |tick| tick[:time] >= options[:start_date] }
  end
  
  if options[:end_date]
    tick_data = tick_data.select { |tick| tick[:time] <= options[:end_date] }
  end
  
  puts "期間フィルタリング: #{original_size}個から#{tick_data.size}個のデータに絞り込みました"
end

# バックテストエンジンの準備
puts "\nバックテストを実行中..."
strategy = MT4Backtester::Strategies::TrevianStrategy.new(params)
backtester = MT4Backtester::Core::Backtester.new(strategy, tick_data)

# バックテスト実行
results = backtester.run

# 結果の表示
puts "\n==== バックテスト結果 ===="
puts "取引回数: #{results[:total_trades]}"
puts "勝率: #{results[:win_rate] ? (results[:win_rate] * 100).round(2) : 0}%"
puts "総利益: $#{results[:total_profit].round(2)}"
puts "最大ドローダウン: $#{results[:max_drawdown].round(2)}"
puts "プロフィットファクター: #{results[:profit_factor] ? results[:profit_factor].round(2) : 'N/A'}"
puts "期待値: #{results[:expected_payoff] ? results[:expected_payoff].round(2) : 'N/A'}"
puts "============================="

# 結果の保存
if options[:output_file]
  require 'json'
  
  # 細かい取引履歴は省略
  output_results = results.dup
  output_results[:trades] = output_results[:trades][0..9] if output_results[:trades]
  
  File.open(options[:output_file], 'w') do |file|
    file.write(JSON.pretty_generate(output_results))
  end
  
  puts "\n結果を保存しました: #{options[:output_file]}"
end

puts "\nバックテスト完了"
