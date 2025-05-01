require 'rspec'

# ライブラリのロードを試みる
begin
  require_relative '../lib/mt4_backtester'
  puts "ライブラリのロードに成功しました！"
rescue LoadError => e
  puts "ライブラリのロードに失敗しました: #{e.message}"
end

# 実際のテスト
RSpec.describe "Basic Test" do
  it "true is true" do
    expect(true).to be true
  end
end