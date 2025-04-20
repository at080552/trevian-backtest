#!/usr/bin/env ruby

require 'optparse'
require 'json'
require_relative '../lib/mt4_backtester'

# コマンドラインオプションのパース
options = {
  result_file: nil,
  tick_file: nil,
  chart_file: nil,
  symbol: 'GBPUSD',
  timeframe: 'M1',
  date_format: '%Y.%m.%d'
}

OptionParser.new do |opts|
  opts.banner = "使用法: ruby generate_chart.rb [options]"
  
  opts.on("-r", "--result FILE", "バックテスト結果JSONファイル") do |file|
    options[:result_file] = file
  end
  
  opts.on("-t", "--tick FILE", "ティックデータファイル") do |file|
    options[:tick_file] = file
  end
  
  opts.on("-c", "--chart FILE", "出力HTMLチャートファイル") do |file|
    options[:chart_file] = file
  end
  
  opts.on("-y", "--symbol SYMBOL", "通貨ペア") do |symbol|
    options[:symbol] = symbol
  end
  
  opts.on("-f", "--timeframe TIMEFRAME", "時間枠") do |timeframe|
    options[:timeframe] = timeframe
  end
  
  opts.on("-d", "--date-format FORMAT", "日付フォーマット") do |format|
    options[:date_format] = format
  end
  
  opts.on("-h", "--help", "ヘルプの表示") do
    puts opts
    exit
  end
end.parse!

# ファイルチェック
if options[:result_file].nil?
  puts "エラー: バックテスト結果ファイルのパスを指定してください (-r または --result オプション)"
  exit 1
end

unless File.exist?(options[:result_file])
  puts "エラー: 指定された結果ファイルが存在しません: #{options[:result_file]}"
  exit 1
end

if options[:tick_file].nil?
  puts "エラー: ティックデータファイルのパスを指定してください (-t または --tick オプション)"
  exit 1
end

unless File.exist?(options[:tick_file])
  puts "エラー: 指定されたティックファイルが存在しません: #{options[:tick_file]}"
  exit 1
end

if options[:chart_file].nil?
  puts "エラー: 出力HTMLチャートファイルのパスを指定してください (-c または --chart オプション)"
  exit 1
end

puts "チャート生成ツール"
puts "==================="
puts "設定:"
puts "- 結果ファイル: #{options[:result_file]}"
puts "- ティックファイル: #{options[:tick_file]}"
puts "- 出力チャートファイル: #{options[:chart_file]}"
puts "- 通貨ペア: #{options[:symbol]}"
puts "- 時間枠: #{options[:timeframe]}"
puts "==================="

# 結果の読み込み
puts "\n結果ファイルを読み込み中..."
results_json = File.read(options[:result_file])
results = JSON.parse(results_json, symbolize_names: true)

# ティックデータの読み込み
puts "ティックデータを読み込み中..."
data_loader = MT4Backtester::Data::HistdataTickData.new(
  options[:symbol],
  options[:timeframe].to_sym
)

tick_data = data_loader.load(options[:tick_file], {
  format: :specific,
  date_format: options[:date_format]
})

# グラフの生成
puts "チャートを生成中..."
chart_data = MT4Backtester::Visualization::ChartDataProcessor.new(results, tick_data)
chart_generator = MT4Backtester::Visualization::HtmlChartGenerator.new(chart_data)

chart_title = "Trevian バックテスト結果 (#{options[:symbol]} #{options[:timeframe]})"
html_content = chart_generator.generate_html(chart_title)

File.write(options[:chart_file], html_content)
puts "チャートを保存しました: #{options[:chart_file]}"
