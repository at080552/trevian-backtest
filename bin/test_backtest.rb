#!/usr/bin/env ruby

require_relative '../lib/mt4_backtester'

puts "Trevianバックテストシステムのテスト"
puts "-------------------------------------"

# パーサーでMT4パラメータを取得
mq4_file = "data/trevian_ZA701.mq4"
parser = MT4Backtester::Parsers::MT4Parser.new(mq4_file)
strategy_data = parser.parse

# パラメータの表示と変換
puts "EA名: #{strategy_data[:name]}"
puts "パラメータ数: #{strategy_data[:parameters].size}"

# パラメータの変換（文字列からハッシュ形式に）
params = {}
strategy_data[:parameters].each do |param|
  key = param[:name].to_sym
  # 値を適切な型に変換
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

# バックテストの実行
puts "\nバックテストを開始します..."
backtester = MT4Backtester::Core::Backtester.new(
  MT4Backtester::Strategies::TrevianStrategy,
  params
)

# 日付範囲の設定（例：最近の1ヶ月）
start_date = Time.now - (60 * 60 * 24 * 30) # 30日前
end_date = Time.now

# バックテストの実行
results = backtester.run(start_date, end_date)

# 詳細結果の表示
puts "\n最初の5取引の詳細:" if results && results[:trades] && !results[:trades].empty?
results[:trades].first(5).each_with_index do |trade, i|
  puts "\n取引 ##{i+1}:"
  puts "  種類: #{trade[:type]}"
  puts "  オープン: #{trade[:open_time]} @ #{trade[:open_price]}"
  puts "  クローズ: #{trade[:close_time]} @ #{trade[:close_price]}"
  puts "  ロットサイズ: #{trade[:lot_size]}"
  puts "  利益: $#{trade[:profit].round(2)}"
end
