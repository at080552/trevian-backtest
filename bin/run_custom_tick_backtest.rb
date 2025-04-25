#!/usr/bin/env ruby

require 'optparse'
require_relative '../lib/mt4_backtester'
# .envから設定を読み込む
env_params = MT4Backtester::Config::ConfigLoader.load

#raise params.inspect
# コマンドラインオプションのパース
options = {
  mq4_file: 'data/trevian_ZA701.mq4',
  data_file: nil,
  start_date: nil,
  end_date: nil,
  output_file: nil,
  chart_file: nil,
  symbol: 'GBPUSD',
  timeframe: 'M1',
  debug_mode: false,
  gap: env_params[:Gap],
  takeprofit: env_params[:Takeprofit],
  start_lots: env_params[:Start_Lots],
  log_file: nil  # ログファイルのパスを追加
}

OptionParser.new do |opts|
  opts.banner = "使用法: ruby run_custom_tick_backtest.rb [options]"
  
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
  
  opts.on("-o", "--output FILE", "出力JSONファイル") do |file|
    options[:output_file] = file
  end
  
  opts.on("-c", "--chart FILE", "出力HTMLチャートファイル") do |file|
    options[:chart_file] = file
  end
  
  opts.on("-y", "--symbol SYMBOL", "通貨ペア") do |symbol|
    options[:symbol] = symbol
  end
  
  opts.on("-t", "--timeframe TIMEFRAME", "時間枠") do |timeframe|
    options[:timeframe] = timeframe
  end
  
  opts.on("-v", "--verbose", "詳細な出力を表示") do
    options[:debug_mode] = true
  end

  opts.on("-l", "--log FILE", "ログ出力ファイルのパス") do |file|
    options[:log_file] = file
  end

  opts.on("-h", "--help", "ヘルプの表示") do
    puts opts
    exit
  end
end.parse!

# ファイルのパスチェック
if options[:data_file].nil?
  puts "エラー: ティックデータファイルのパスを指定してください (-d または --data オプション)"
  exit 1
end

unless File.exist?(options[:data_file])
  puts "エラー: 指定されたファイルが存在しません: #{options[:data_file]}"
  exit 1
end

puts "Trevianバックテスト実行（カスタムティックデータを使用）"
puts "==========================================="
puts "設定:"
puts "- MT4ファイル: #{options[:mq4_file]}"
puts "- ティックデータファイル: #{options[:data_file]}"
puts "- 期間: #{options[:start_date] ? options[:start_date].strftime('%Y-%m-%d') : '全期間'} から #{options[:end_date] ? options[:end_date].strftime('%Y-%m-%d') : '全期間'}"
puts "- 通貨ペア: #{options[:symbol]}"
puts "- 時間枠: #{options[:timeframe]}"
puts "- グラフ出力: #{options[:chart_file] ? options[:chart_file] : '未指定'}"
puts "==========================================="

# MT4ファイルのパース
puts "\nMT4ファイルを解析中..."
parser = MT4Backtester::Parsers::MT4Parser.new(options[:mq4_file])
strategy_data = parser.parse

puts "EA名: #{strategy_data[:name]}"
puts "パラメータ数: #{strategy_data[:parameters].size}"

# MT4ファイルから読み込んだパラメータを変換
mt4_params = {}
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
  mt4_params[key] = value
end

# 優先順位: MT4ファイル < .env < コマンドライン引数
params = mt4_params.merge(env_params) # .envの値でMT4の値を上書き

# 計算パラメータを表示
puts "\n===== 計算されたパラメータ ====="
puts "Gap: #{params[:Gap]}"
puts "GapProfit: #{params[:Takeprofit]}"
puts "next_order_keisu: #{((params[:Gap] + params[:Takeprofit]) / params[:Takeprofit]) * params[:keisu_x]}"
puts "===================================="

# カスタムティックデータの読み込み
puts "\nティックデータを読み込み中..."
data_loader = MT4Backtester::Data::CustomTickData.new(
  options[:symbol],
  options[:timeframe].to_sym
)

# データ読み込み
tick_data = data_loader.load(options[:data_file])

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

# 空のデータセットをチェック
if tick_data.empty?
  puts "エラー: 有効なティックデータがありません。データ形式を確認するか、期間を調整してください。"
  exit 1
end

# バックテストエンジンの準備
puts "\nバックテストを実行中..."
strategy = MT4Backtester::Strategies::TrevianStrategy.new(params, options[:debug_mode])
backtester = MT4Backtester::Core::Backtester.new(strategy, tick_data)

# ロガーパスを設定
backtester.logger_path = options[:log_file] if options[:log_file]
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

# トレード詳細を表示
if results[:trades] && !results[:trades].empty?
  puts "\n最初の5取引の詳細:"
  results[:trades].first(5).each_with_index do |trade, i|
    puts "\n取引 ##{i+1}:"
    puts "  種類: #{trade[:type]}"
    puts "  オープン: #{trade[:open_time]} @ #{trade[:open_price]}"
    puts "  クローズ: #{trade[:close_time]} @ #{trade[:close_price]}"
    puts "  ロットサイズ: #{trade[:lot_size]}"
    puts "  利益: $#{trade[:profit].round(2)}"
  end
end

# グラフの生成
if options[:chart_file]
  puts "\nバックテスト結果のグラフを生成中..."
  chart_data = MT4Backtester::Visualization::ChartDataProcessor.new(results, tick_data)
  chart_generator = MT4Backtester::Visualization::HtmlChartGenerator.new(chart_data)
  
  chart_title = "Trevian バックテスト結果 (#{options[:symbol]} #{options[:timeframe]})"
  html_content = chart_generator.generate_html(chart_title)
  
  begin
    # 出力ディレクトリがなければ作成
    output_dir = File.dirname(options[:chart_file])
    unless File.directory?(output_dir)
      FileUtils.mkdir_p(output_dir)
    end
    
    File.write(options[:chart_file], html_content)
    puts "グラフを保存しました: #{options[:chart_file]}"
  rescue => e
    puts "グラフ保存中にエラーが発生しました: #{e.message}"
  end
end

# 結果の保存
if options[:output_file]
  require 'json'
  
  # 完全な結果を保存
  output_results = results.dup
  
  begin
    # 出力ディレクトリがなければ作成
    output_dir = File.dirname(options[:output_file])
    unless File.directory?(output_dir)
      FileUtils.mkdir_p(output_dir)
    end
    
    File.write(options[:output_file], JSON.pretty_generate(output_results))
    puts "\n結果を保存しました: #{options[:output_file]}"
  rescue => e
    puts "結果保存中にエラーが発生しました: #{e.message}"
  end
end

puts "\nバックテスト完了"
