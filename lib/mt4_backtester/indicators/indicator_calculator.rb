module MT4Backtester
  module Indicators
    class IndicatorCalculator
      attr_reader :indicators, :candles
      
      def initialize
        @indicators = {}
        @candles = []
      end
      
      # ローソク足データを設定
      def set_candles(candles)
        @candles = candles
        calculate_all
      end
      
      # 移動平均を追加
      def add_ma(name, period, price_type = :close)
        @indicators[name] = MovingAverage.new(period, price_type)
        calculate(@indicators[name]) if @candles.any?
        @indicators[name]
      end
      
      # 指標を計算
      def calculate(indicator)
        indicator.calculate(@candles)
      end
      
      # すべての指標を計算
      def calculate_all
        @indicators.each_value do |indicator|
          calculate(indicator)
        end
      end
      
      # 現在の値を取得
      def value(name)
        return nil unless @indicators[name]
        @indicators[name].current_value
      end
      
      # 前回値を取得
      def previous_value(name)
        return nil unless @indicators[name]
        @indicators[name].previous_value
      end
      
      # 移動平均クロスオーバーの確認（Trevian方式）
      def ma_crossover_check(fast_ma_name, slow_ma_name)
        fast_ma = @indicators[fast_ma_name]
        slow_ma = @indicators[slow_ma_name]
        
        return :none if fast_ma.nil? || slow_ma.nil?
        
        # Trevianのロジック: 現在と前回の両方でFastMAがSlowMAの上にある場合は買い
        if fast_ma.above?(slow_ma, 2)
          return :buy
        else
          return :sell  # Trevianでは他のケースは全て売り
        end
      end
    end
  end
end
