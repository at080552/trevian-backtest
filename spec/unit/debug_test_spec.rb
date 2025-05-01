require_relative '../helpers/spec_helper'

# まずプロジェクトの構造を調査
puts "プロジェクトルート: #{File.expand_path('../..', __FILE__)}"
puts "ライブラリのパス: #{File.expand_path('../../lib', __FILE__)}"

# libディレクトリのファイル一覧を取得
puts "libディレクトリにあるファイル:"
Dir["#{File.expand_path('../../lib', __FILE__)}/**/*.rb"].sort.each do |file|
  puts "  - #{file}"
end

RSpec.describe "MT4 EA デバッグテスト" do
  it "基本テスト - 常に成功" do
    expect(true).to eq(true)
  end
  
  it "ライブラリのロード状況を確認" do
    # ライブラリがロードできているかどうか
    if defined?(MT4Backtester)
      puts "MT4Backtesterモジュールが定義されています"
      
      # モジュールの中身を調査
      puts "使用可能なモジュール:"
      MT4Backtester.constants.sort.each do |const|
        puts "  - MT4Backtester::#{const}"
      end
      
      expect(defined?(MT4Backtester)).to eq("constant")
    else
      puts "MT4Backtesterモジュールが定義されていません"
      skip "MT4Backtesterモジュールが見つからないためテストをスキップします"
    end
  end
end
