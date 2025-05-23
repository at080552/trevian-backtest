module MT4Backtester
  module Indicators
    class MT4CompatibleMA
      attr_reader :data, :period, :ma_method, :price_type, :shift
      
      # MT4のiMA関数に準拠したコンストラクタ
      # @param period [Integer] 移動平均の期間
      # @param ma_method [Symbol] 移動平均の計算方法 (:sma, :ema, :smma, :lwma)
      # @param price_type [Symbol] 使用する価格タイプ (:close, :open, :high, :low, etc.)
      # @param shift [Integer] シフト値
      def initialize(period = 14, ma_method = :sma, price_type = :close, shift = 0)
        @period = period
        @ma_method = ma_method
        @price_type = price_type
        @shift = shift
        @data = []
        @buffer = [] # 計算用バッファ
      end
      
      # MT4のiMA関数と同様の計算ロジックを実装
      # @param candles [Array] ローソク足データの配列
      # @return [Array] 計算された移動平均値の配列
      def calculate(candles)
        return [] if candles.empty?
        
        @data = []
        
        # シフト値を適用したインデックスで計算
        effective_candles = candles.clone
        
        # 使用する価格タイプに基づいて価格配列を生成
        prices = extract_prices(effective_candles)
        
        # 移動平均の計算方法に基づいて計算
        case @ma_method
        when :sma
          calculate_sma(prices)
        when :ema
          calculate_ema(prices)
        when :smma
          calculate_smma(prices)
        when :lwma
          calculate_lwma(prices)
        else
          # デフォルトはSMA
          calculate_sma(prices)
        end
        
        @data
      end
      
      # 特定のインデックスの移動平均値を取得（MT4のiMA関数と同様）
      # @param index [Integer] 取得したいバーのインデックス（0が最新）
      # @return [Float, nil] 移動平均値
      def current_value
        return nil if @data.empty?
        
        # 最新の有効な値を取得（後ろから5個まで確認）
        @data.reverse.first(5).each do |value|
          if value && value.is_a?(Numeric) && value.finite? && value > 0
            return value
          end
        end
        
        nil
      end

      def previous_value(steps_back = 1)
        return nil if @data.length <= steps_back
        
        # 指定されたステップ数だけ前の有効な値を取得
        start_index = [@data.length - 1 - steps_back, 0].max
        end_index = [@data.length - 1, start_index].max
        
        (start_index..end_index).reverse_each do |i|
          value = @data[i]
          if value && value.is_a?(Numeric) && value.finite? && value > 0
            return value
          end
        end
        
        nil
      end


      # 特定のインデックスの移動平均値を取得（MT4のiMA関数と同様）
      def value(index = 0)
        return nil if @data.empty?
        
        # 負のインデックスは配列の後ろから
        if index < 0
          idx = @data.length + index
        else
          # MT4風のインデックス（0が最新）
          idx = @data.length - 1 - index
        end
        
        return nil if idx < 0 || idx >= @data.length
        
        value = @data[idx]
        return value if value && value.is_a?(Numeric) && value.finite?
        
        nil
      end

      # データの有効性をチェックするメソッドを追加
      def has_valid_data?
        return false if @data.empty?
        
        # 最新の10個のデータをチェック
        recent_data = @data.last(10).compact
        return false if recent_data.empty?
        
        # すべて同じ値でないかチェック
        first_value = recent_data.first
        all_same = recent_data.all? { |v| (v - first_value).abs < 0.000001 }
        
        !all_same
      end

      # デバッグ用：データの統計情報を取得
      def debug_info
        return "No data" if @data.empty?
        
        valid_data = @data.compact
        return "No valid data" if valid_data.empty?
        
        {
          total_count: @data.length,
          valid_count: valid_data.length,
          min: valid_data.min,
          max: valid_data.max,
          latest: current_value,
          has_variation: has_valid_data?
        }
      end

      private
      
      # ローソク足から価格データを抽出
      def extract_prices(candles)
        candles.map do |candle|
          case @price_type
          when :open
            candle[:open]
          when :high
            candle[:high]
          when :low
            candle[:low]
          when :close
            candle[:close]
          when :median
            (candle[:high] + candle[:low]) / 2.0
          when :typical
            (candle[:high] + candle[:low] + candle[:close]) / 3.0
          when :weighted
            (candle[:high] + candle[:low] + candle[:close] * 2) / 4.0
          else
            # デフォルトは終値
            candle[:close]
          end
        end
      end
      
      # 単純移動平均（SMA）の計算
      # calculate_sma メソッドにデバッグ機能を追加
      def calculate_sma(prices)
        @data = []
        
        return @data if prices.length < @period
        
        # デバッグ: 入力価格の確認
        if defined?(@debug_mode) && @debug_mode
          puts "SMA計算: 期間=#{@period}, 価格数=#{prices.length}"
          puts "最新5価格: #{prices.last(5)}" if prices.length >= 5
          puts "全価格範囲: #{prices.min} - #{prices.max}"
        end
        
        # 各バーでのSMAを計算
        (0...prices.length).each do |i|
          if i < @period - 1
            @data << nil
          else
            # 単純平均を計算 - 正しい順序で計算
            sum = 0.0
            used_prices = []
            
            @period.times do |j|
              idx = i - (@period - 1) + j  # 正しいインデックス計算
              if idx >= 0 && idx < prices.length
                sum += prices[idx]
                used_prices << prices[idx]
              end
            end
            
            # ゼロ除算チェック
            if used_prices.length > 0
              sma_value = sum / used_prices.length
              @data << sma_value
              
              # デバッグ: 計算過程の表示（重要なポイントのみ）
              if defined?(@debug_mode) && @debug_mode && (i == @period - 1 || i % 100 == 0)
                puts "SMA[#{i}]: 使用価格数=#{used_prices.length}, 合計=#{sum.round(5)}, SMA=#{sma_value.round(5)}"
                puts "  価格範囲: #{used_prices.min.round(5)} - #{used_prices.max.round(5)}"
              end
            else
              @data << nil
            end
          end
        end
        
        # 最終確認
        if defined?(@debug_mode) && @debug_mode
          non_nil_data = @data.compact
          if non_nil_data.any?
            puts "SMA計算完了: 有効データ数=#{non_nil_data.length}, 範囲=#{non_nil_data.min.round(5)} - #{non_nil_data.max.round(5)}"
          else
            puts "警告: SMA計算で有効なデータが生成されませんでした"
          end
        end
        
        @data
      end
      
      # 指数移動平均（EMA）の計算
      def calculate_ema(prices)
        @data = []
        
        # 十分なデータがあるかチェック
        return @data if prices.length < @period
        
        # 最初のEMAはSMAと同じ
        sma_value = 0.0
        @period.times do |i|
          sma_value += prices[i]
        end
        sma_value /= @period
        
        # 最初のEMAをセット
        @data = Array.new(@period - 1, nil) + [sma_value]
        
        # 係数を計算 (MT4のEMA計算方法に合わせる)
        # α = 2/(N+1)
        alpha = 2.0 / (@period + 1.0)
        
        # 残りのEMAを計算
        (@period...prices.length).each do |i|
          # EMA(today) = α × 今日の価格 + (1-α) × EMA(yesterday)
          ema = alpha * prices[i] + (1.0 - alpha) * @data.last
          @data << ema
        end
        
        @data
      end
      
      # 平滑移動平均（SMMA）の計算
      def calculate_smma(prices)
        @data = []
        
        # 十分なデータがあるかチェック
        return @data if prices.length < @period
        
        # 最初のSMMAはSMAと同じ
        sum = 0.0
        @period.times do |i|
          sum += prices[i]
        end
        first_smma = sum / @period
        
        # 最初のSMMAをセット
        @data = Array.new(@period - 1, nil) + [first_smma]
        
        # 残りのSMMAを計算
        (@period...prices.length).each do |i|
          # SMMA(i) = (SMMA(i-1) * (N-1) + PRICE(i)) / N
          smma = (@data.last * (@period - 1) + prices[i]) / @period
          @data << smma
        end
        
        @data
      end
      
      # 線形加重移動平均（LWMA）の計算
      def calculate_lwma(prices)
        @data = []
        
        # 十分なデータがあるかチェック
        return @data if prices.length < @period
        
        # 各バーでのLWMAを計算
        (0...prices.length).each do |i|
          if i < @period - 1
            # 期間に満たない場合はnilをセット
            @data << nil
          else
            # 加重平均を計算
            weighted_sum = 0.0
            weight_sum = 0
            
            @period.times do |j|
              weight = @period - j
              idx = i - j
              weighted_sum += prices[idx] * weight
              weight_sum += weight
            end
            
            @data << (weighted_sum / weight_sum)
          end
        end
        
        @data
      end
    end
  end
end