#!/usr/bin/env ruby

# ライブラリを直接読み込み
require_relative '../lib/mt4_backtester'

# MQ4ファイルのパス
mq4_file = ARGV[0] || "data/trevian_ZA701.mq4"

unless File.exist?(mq4_file)
  puts "エラー: MQ4ファイルが見つかりません: #{mq4_file}"
  puts "現在のディレクトリ: #{Dir.pwd}"
  puts "ファイルパス: #{mq4_file}"
  exit 1
end

puts "MT4ファイルパーサーのテスト"
puts "解析対象: #{mq4_file}"
puts "--------------------------"

# パーサーの実行
parser = MT4Backtester::Parsers::MT4Parser.new(mq4_file)
strategy = parser.parse

# 結果の表示
puts "\n==== 解析結果 ===="
puts "EA名: #{strategy[:name]}"
puts "\nパラメータ一覧 (#{strategy[:parameters].size}):"
strategy[:parameters].each do |param|
  puts "  - #{param[:name]} (#{param[:type]}): #{param[:default_value]}"
end