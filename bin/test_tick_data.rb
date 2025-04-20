#!/usr/bin/env ruby

require_relative '../lib/mt4_backtester'

# コマンドライン引数からファイルパスを取得
file_path = ARGV[0]

if file_path.nil? || !File.exist?(file_path)
  puts "使用法: ruby test_tick_data.rb <ティックデータファイルのパス>"
  puts "例: ruby test_tick_data.rb data/GBPUSD_M1_2023.csv"
  exit 1
end

puts "ティックデータ読み込みテスト"
puts "ファイル: #{file_path}"
puts "-----------------------"

# ファイルの拡張子に基づいて適切なローダーを選択
loader = MT4Backtester::Data::TickDataFactory.create_loader(file_path)

# データを読み込む
data = loader.load(file_path)

# データの要約を表示
loader.print_summary

# 最初の5つのティックデータを表示
puts "\n最初の5つのティック:"
data.first(5).each_with_index do |tick, i|
  puts "Tick ##{i+1}: #{tick[:time]} - O: #{tick[:open]} H: #{tick[:high]} L: #{tick[:low]} C: #{tick[:close]} V: #{tick[:volume]}"
end

puts "\n最後の5つのティック:"
data.last(5).each_with_index do |tick, i|
  puts "Tick ##{data.size-5+i+1}: #{tick[:time]} - O: #{tick[:open]} H: #{tick[:high]} L: #{tick[:low]} C: #{tick[:close]} V: #{tick[:volume]}"
end

# データのサンプリング（1時間ごと）
puts "\n1時間ごとのサンプリング:"
hour_samples = {}

data.each do |tick|
  hour_key = tick[:time].strftime('%Y-%m-%d %H:00')
  hour_samples[hour_key] ||= tick
end

hour_samples.keys.sort.first(10).each do |key|
  tick = hour_samples[key]
  puts "#{key} - O: #{tick[:open]} H: #{tick[:high]} L: #{tick[:low]} C: #{tick[:close]}"
end

puts "\nティックデータ読み込みテスト完了"
