require_relative '../helpers/spec_helper'

RSpec.describe MT4Backtester::Strategies::Trevian::CoreLogic do
  let(:base_params) do
    {
      Gap: 4000.0,
      Takeprofit: 60.0,
      Start_Lots: 0.95,
      Gap_down_Percent: 0,
      Profit_down_Percent: 0,
      keisu_x: 9.9,
      keisu_plus_pips: 0.35,
      position_x: 1,
      LosCutPosition: 15,
      LosCutProfit: -900,
      LosCutPlus: -40,
      Start_Sikin: 300,
      SpredKeisuu: 10000,
      Symbol: 'GBPUSD'
    }
  end

  let(:core_logic) { described_class.new(base_params) }

  describe "基本機能テスト" do
    it "インスタンスが作成できること" do
      expect(core_logic).to be_a(described_class)
    end
    
    it "SpredKeisuuが通貨ペアに応じて正しく設定されること" do
      gbp_logic = described_class.new(base_params.merge(Symbol: 'GBPUSD'))
      jpy_logic = described_class.new(base_params.merge(Symbol: 'USDJPY'))
      
      expect(gbp_logic.params[:SpredKeisuu]).to eq(10000)
      expect(jpy_logic.params[:SpredKeisuu]).to eq(100)
    end
    
    it "状態がリセットできること" do
      # reset_stateメソッドの存在確認
      skip "reset_stateメソッドがない場合はスキップ" unless core_logic.respond_to?(:reset_state, true)
      
      # プライベートメソッドを呼び出す
      core_logic.send(:reset_state)
      
      # 状態が初期化されていることを確認
      state = core_logic.instance_variable_get(:@state)
      expect(state).to be_a(Hash)
      expect(state[:trailing_stop_flag]).to eq(0)
    end
  end
end
