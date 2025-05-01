require_relative '../helpers/spec_helper'

RSpec.describe MT4Backtester::Indicators::MT4CompatibleMA do
  let(:period) { 5 }
  let(:ma_method) { :sma }
  let(:price_type) { :close }
  
  let(:ma_indicator) { described_class.new(period, ma_method, price_type) }
  
  describe '基本機能' do
    it 'インスタンスが作成できること' do
      expect(ma_indicator).to be_a(described_class)
    end
    
    it '期間が正しく設定されること' do
      expect(ma_indicator.period).to eq(period)
    end
    
    it 'MA方式が正しく設定されること' do
      expect(ma_indicator.ma_method).to eq(ma_method)
    end
    
    it '価格タイプが正しく設定されること' do
      expect(ma_indicator.price_type).to eq(price_type)
    end
  end
  
  describe '#calculate' do
    let(:candles) do
      [
        { time: Time.new(2023, 1, 1, 10, 0), open: 1.2500, high: 1.2510, low: 1.2490, close: 1.2505 },
        { time: Time.new(2023, 1, 1, 10, 1), open: 1.2505, high: 1.2515, low: 1.2495, close: 1.2510 },
        { time: Time.new(2023, 1, 1, 10, 2), open: 1.2510, high: 1.2520, low: 1.2500, close: 1.2515 },
        { time: Time.new(2023, 1, 1, 10, 3), open: 1.2515, high: 1.2525, low: 1.2505, close: 1.2520 },
        { time: Time.new(2023, 1, 1, 10, 4), open: 1.2520, high: 1.2530, low: 1.2510, close: 1.2525 }
      ]
    end
    
    it '空のデータ配列を返すことができる' do
      # 空のローソク足データで計算
      result = ma_indicator.calculate([])
      expect(result).to be_an(Array)
    end
    
    it 'ローソク足データに対して計算を実行できる' do
      # 計算メソッドが動作することを確認
      result = ma_indicator.calculate(candles)
      expect(result).to be_an(Array)
    end
  end
end
