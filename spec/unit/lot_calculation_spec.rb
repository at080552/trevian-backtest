require_relative '../helpers/spec_helper'

RSpec.describe MT4Backtester::Strategies::Trevian::CoreLogic do
  # テストで使用する基本パラメータ
  let(:base_params) do
    {
      Gap: 4000.0,
      Takeprofit: 60.0,
      Start_Lots: 0.95,
      Gap_down_Percent: 0,
      Profit_down_Percent: 0,
      keisu_x: 9.9,
      keisu_pulus_pips: 0.35,
      position_x: 1,
      LosCutPosition: 15,
      LosCutProfit: -900.0,
      LosCutPlus: -40.0,
      Start_Sikin: 300,
      SpredKeisuu: 10000,
      Symbol: 'GBPUSD',
      fukuri: 1.0,
      MaxLotX: 18.0
    }
  end

  # テスト対象のクラスのインスタンスを作成
  let(:core_logic) { described_class.new(base_params) }

  describe '#calculate_lot_size' do
    context '基本設定での計算' do
      it '期待通りの初期ロットを返す' do
        # コードが存在するか確認
        expect(core_logic).to respond_to(:calculate_lot_size)
        
        # テスト前にfukuriパラメータを明示的に設定
        core_logic.instance_variable_set(:@params, base_params)
        
        # calculate_lot_sizeメソッドが存在しない場合は、テストをスキップ
        skip "calculate_lot_sizeメソッドが実装されていません" unless core_logic.respond_to?(:calculate_lot_size)
        
        # MT4での結果値と一致するか検証
        expected_lot = 0.95  # MT4から取得した期待値
        actual_lot = core_logic.calculate_lot_size
        
        # 小数点以下の誤差を許容
        expect(actual_lot).to be_within(0.01).of(expected_lot)
      end
    end
  end
end
