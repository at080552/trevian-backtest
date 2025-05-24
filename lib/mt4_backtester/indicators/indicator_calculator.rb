module MT4Backtester
  module Indicators
    class IndicatorCalculator
      attr_reader :indicators, :candles
      
      def initialize(debug_mode = false)
        @indicators = {}
        @candles = []
        @debug_mode = debug_mode
      end

      def add_indicator(name, indicator)
        @indicators[name] = indicator
        
        # デバッグモードを伝播
        if indicator.respond_to?(:instance_variable_set)
          indicator.instance_variable_set(:@debug_mode, @debug_mode)
        end
        
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
        # 新しいMT4互換クラスを使用
        ma_indicator = MT4CompatibleMA.new(period, :sma, price_type)
        
        # デバッグモードを設定
        ma_indicator.instance_variable_set(:@debug_mode, @debug_mode) if @debug_mode
        
        @indicators[name] = ma_indicator
        calculate(ma_indicator) if @candles.any?
        ma_indicator
      end
      
      # 指標を計算
      def calculate(indicator)
        old_data_size = indicator.respond_to?(:data) ? indicator.data.size : 0
        
        indicator.calculate(@candles)
        
        # デバッグ情報
        if @debug_mode && indicator.respond_to?(:data)
          new_data_size = indicator.data.size
          if new_data_size != old_data_size
            puts "インジケーター計算更新: データ数 #{old_data_size} → #{new_data_size}"
            
            if indicator.respond_to?(:debug_info)
              puts "  詳細: #{indicator.debug_info}"
            end
          end
        end
      end
      
      # すべての指標を計算
      def calculate_all
        return if @candles.empty?
        
        if @debug_mode
          puts "全インジケーター計算開始: ローソク足数=#{@candles.size}"
        end
        
        @indicators.each do |name, indicator|
          calculate(indicator)
          
          if @debug_mode && indicator.respond_to?(:current_value)
            current_val = indicator.current_value
            puts "  #{name}: #{current_val ? current_val.round(5) : 'nil'}"
          end
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

      # 残りのメソッドは変更なし
      def ma_crossover_check(fast_ma_name, slow_ma_name)
        fast_ma = @indicators[fast_ma_name]
        slow_ma = @indicators[slow_ma_name]
        
        return :sell if fast_ma.nil? || slow_ma.nil?
      
        # 現在と前回の値を取得
        fast_ma_current = fast_ma.current_value
        fast_ma_prev = fast_ma.previous_value
        slow_ma_current = slow_ma.current_value
        slow_ma_prev = slow_ma.previous_value
      
        # デバッグ出力を追加
        if @debug_mode
          puts "MA Check - Current: FastMA=#{fast_ma_current}, SlowMA=#{slow_ma_current}, FastMA > SlowMA: #{fast_ma_current > slow_ma_current}"
          puts "MA Check - Previous: FastMA=#{fast_ma_prev}, SlowMA=#{slow_ma_prev}, FastMA > SlowMA: #{fast_ma_prev > slow_ma_prev}"
        end
      
        # 両方の条件を確認して一致したシグナルを返す
        if fast_ma_current > slow_ma_current && fast_ma_prev > slow_ma_prev
          return :buy
        else
          return :sell
        end
      end
    end
  end
end
