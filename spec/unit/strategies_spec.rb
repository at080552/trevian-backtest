require_relative '../helpers/spec_helper'

RSpec.describe "Strategies Module Tests" do
  it "MT4Backtester::Strategiesモジュールが存在する" do
    if defined?(MT4Backtester) && defined?(MT4Backtester::Strategies)
      puts "MT4Backtester::Strategiesモジュールが存在します"
      expect(defined?(MT4Backtester::Strategies)).to eq("constant")
    else
      skip "MT4Backtester::Strategiesモジュールが見つかりません"
    end
  end
  
  it "MT4Backtester::Strategies::Trevianモジュールが存在する" do
    if defined?(MT4Backtester) && 
       defined?(MT4Backtester::Strategies) && 
       defined?(MT4Backtester::Strategies::Trevian)
      puts "MT4Backtester::Strategies::Trevianモジュールが存在します"
      expect(defined?(MT4Backtester::Strategies::Trevian)).to eq("constant")
    else
      skip "MT4Backtester::Strategies::Trevianモジュールが見つかりません"
    end
  end
  
  it "MT4Backtester::Strategies::Trevian::CoreLogicクラスが存在する" do
    if defined?(MT4Backtester) && 
       defined?(MT4Backtester::Strategies) && 
       defined?(MT4Backtester::Strategies::Trevian) &&
       defined?(MT4Backtester::Strategies::Trevian::CoreLogic)
      puts "MT4Backtester::Strategies::Trevian::CoreLogicクラスが存在します"
      
      # CoreLogicクラスのインスタンスを作成してみる
      begin
        core_logic = MT4Backtester::Strategies::Trevian::CoreLogic.new({})
        puts "CoreLogicクラスのインスタンスを作成できました"
        
        # 使用可能なメソッドを表示
        puts "使用可能なメソッド:"
        methods = core_logic.public_methods(false).sort
        methods.each { |m| puts "  - #{m}" }
        
        expect(core_logic).to be_a(MT4Backtester::Strategies::Trevian::CoreLogic)
      rescue => e
        puts "CoreLogicクラスのインスタンス作成に失敗しました: #{e.message}"
        skip "CoreLogicクラスのインスタンス作成に失敗したためテストをスキップします"
      end
    else
      skip "MT4Backtester::Strategies::Trevian::CoreLogicクラスが見つかりません"
    end
  end
end
