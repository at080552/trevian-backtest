#!/usr/bin/env ruby

require_relative '../lib/mt4_backtester'

# コマンドライン引数からファイルパスを取得
file_path = ARGV[0]

if file_path.nil? || !File.exist?(file_path)
  puts "使用法: ruby run_histdata_test.rb <データファイルのパス>"
  exit 1
end

puts "HistDataフォーマットテスト"
puts "ファイル: #{file_path}"
puts "-----------------------"

# HistDataローダーを作成
loader = MT4Backtester::Data::HistdataTickData.new('GBPUSD', :M1)

# データの読み込み（特殊フォーマット指定）
data = loader.load(file_path, {
  format: :specific,
  date_format: '%Y.%m.%d'
})

# データの要約を表示
loader.print_summary

# サンプルデータの表示
puts "\n最初の5つのティック:"
data.first(5).each_with_index do |tick, i|
  puts "Tick ##{i+1}: #{tick[:time]} - O: #{tick[:open]} H: #{tick[:high]} L: #{tick[:low]} C: #{tick[:close]} V: #{tick[:volume]}"
end

puts "\nFX価格変動グラフのサンプル（10ポイント）:"
puts "時間               | 価格"
puts "-------------------|--------------------"

# 10個のデータポイントを表示
sample_interval = data.size / 10
10.times do |i|
  index = i * sample_interval
  next if index >= data.size
  
  tick = data[index]
  bar = "#" * (tick[:close] * 100).to_i
  puts "#{tick[:time].strftime('%Y-%m-%d %H:%M')} | #{tick[:close]} #{bar}"
end

puts "\nヒストリカルデータ読み込みテスト完了"
