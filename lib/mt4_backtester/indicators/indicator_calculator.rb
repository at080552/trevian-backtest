module MT4Backtester
  module Indicators
    class IndicatorCalculator
      attr_reader :indicators, :candles
      
      def initialize
        @indicators = {}
        @candles = []
      end

      def add_indicator(name, indicator)
        @indicators[name] = indicator
        calculate(@indicators[name]) if @candles.any?
        @indicators[name]
      end
      
      # ローソク足データを設定
      def set_candles(candles)
        @candles = candles
        calculate_all
      end
      
      # 移動平均を追加
      def add_ma(name, period, price_type = :close)
        # 既存のMovingAverageクラスの代わりにMT4CompatibleMAを使用
        # @indicators[name] = MovingAverage.new(period, price_type)
        
        # 新しいMT4互換クラスを使用
        @indicators[name] = MT4CompatibleMA.new(period, :sma, price_type)
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

      def value(name)
        return nil unless @indicators[name]
        
        # インジケーターの種類によって適切なメソッドを呼び出す
        if @indicators[name].respond_to?(:current_value)
          @indicators[name].current_value
        elsif @indicators[name].respond_to?(:value)
          @indicators[name].value(0)  # 最新の値（インデックス0）
        else
          nil
        end
      end

      # 前回値を取得（ステップ数指定可能）
      def previous_value(name, steps_back = 1)
        return nil unless @indicators[name]
        @indicators[name].value(steps_back)
      end

      def ma_crossover_check(fast_ma_name, slow_ma_name)
        fast_ma = @indicators[fast_ma_name]
        slow_ma = @indicators[slow_ma_name]
        
        return :sell if fast_ma.nil? || slow_ma.nil?
      
        # インデックス1と2の値を取得（MT4と同じ）
        fast_ma1 = fast_ma.value(1)
        fast_ma2 = fast_ma.value(2)
        slow_ma1 = slow_ma.value(1)
        slow_ma2 = slow_ma.value(2)

        # データが揃っていなければデフォルト値を返す（初期データ不足の場合）
        if fast_ma1.nil? || fast_ma2.nil? || slow_ma1.nil? || slow_ma2.nil?
          # 履歴データが不足している場合は、デフォルトのシグナルを返す
          # または十分なデータが揃うまで待つという選択も可能
          return :sell  # または :buy か :sell をデフォルトとして返す
        end

        # MT4と完全に同一の条件判定
        if fast_ma2 > slow_ma2 && fast_ma1 > slow_ma1
          return :buy
        else
          return :sell
        end
      end

      # 移動平均クロスオーバーの確認（Trevian方式）
      def ma_crossover_check_org(fast_ma_name, slow_ma_name)
        fast_ma = @indicators[fast_ma_name]
        slow_ma = @indicators[slow_ma_name]
        
        return :none if fast_ma.nil? || slow_ma.nil?

        # 現在の値を取得
        current_fast = fast_ma.current_value
        current_slow = slow_ma.current_value
        
        # 前回の値を取得
        prev_fast = fast_ma.previous_value
        prev_slow = slow_ma.previous_value

        # デバッグ出力
        if @debug_mode
          puts "現在 FastMA: #{current_fast}, SlowMA: #{current_slow}"
          puts "前回 FastMA: #{prev_fast}, SlowMA: #{prev_slow}"
        end

        # MT4と同様に、必ず買いか売りのどちらかを返すように修正
        if current_fast >= current_slow && prev_fast >= prev_slow
          return :buy
        else
          # それ以外はすべて売り
          return :sell
        end
        # クロスオーバー検出（原MQL4コードに忠実に）
        #if current_fast > current_slow && prev_fast > prev_slow
        #  return :buy
        #elsif current_fast < current_slow && prev_fast < prev_slow
        #  return :sell
        #else
        #  return :none  # 明確なシグナルがない場合
        #end

      end

    end
  end
end
