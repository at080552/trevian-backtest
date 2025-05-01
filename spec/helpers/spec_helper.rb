require 'rspec'

# プロジェクトルートへのパスを取得
project_root = File.expand_path('../..', __dir__)

# ライブラリのパスを追加
lib_path = File.join(project_root, 'lib')
$LOAD_PATH.unshift(lib_path) unless $LOAD_PATH.include?(lib_path)

begin
  require 'mt4_backtester'
  puts "mt4_backtesterのロードに成功しました"
rescue LoadError => e
  puts "mt4_backtesterのロードに失敗しました: #{e.message}"
  
  # 直接ファイルをrequireしてみる
  begin
    require File.join(lib_path, 'mt4_backtester')
    puts "直接requireで成功しました"
  rescue LoadError => e
    puts "直接requireも失敗しました: #{e.message}"
  end
end

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.default_formatter = "doc"
  config.order = :random
  Kernel.srand config.seed
end
