module MT4Backtester
  module Indicators
    class MovingAverage
      attr_reader :data, :period, :price_type
      
      def initialize(period = 14, price_type = :close)
        @period = period
        @price_type = price_type
        @data = []
      end
      
      def calculate(price_data)
        @data = []
        return @data if price_data.empty?
        
        # 期間が足りない場合は、可能な限り計算
        (0...price_data.length).each do |i|
          if i < @period - 1
            # データが不足している場合はnilをセット
            @data << nil
          else
            # 移動平均計算
            sum = 0
            (@period).times do |j|
              idx = i - j
              sum += price_data[idx][@price_type] if idx >= 0 && idx < price_data.length
            end
            @data << sum / @period
          end
        end
        
        @data
      end
      
      def value(index = 0)
        # 最新の値を返す（デフォルト）または指定されたインデックスの値
        index = @data.length - 1 - index if index >= 0
        return nil if index < 0 || index >= @data.length
        @data[index]
      end
      
      def current_value
        @data.empty? ? nil : @data.last
      end
      
      def previous_value
        @data.length < 2 ? nil : @data[-2]
      end
      
      # 別の移動平均とのクロスオーバー確認
      def crossed_above?(other_ma, index = 0)
        current_idx = @data.length - 1 - index
        return false if current_idx < 1 || current_idx >= @data.length
        return false if current_idx >= other_ma.data.length
        
        # 現在: 自分 > 他のMA、前回: 自分 <= 他のMA
        @data[current_idx] > other_ma.data[current_idx] && 
        @data[current_idx - 1] <= other_ma.data[current_idx - 1]
      end
      
      def crossed_below?(other_ma, index = 0)
        current_idx = @data.length - 1 - index
        return false if current_idx < 1 || current_idx >= @data.length
        return false if current_idx >= other_ma.data.length
        
        # 現在: 自分 < 他のMA、前回: 自分 >= 他のMA
        @data[current_idx] < other_ma.data[current_idx] && 
        @data[current_idx - 1] >= other_ma.data[current_idx - 1]
      end
      
      # 連続して上回る/下回るの確認
      def above?(other_ma, count = 2)
        return false if @data.length < count || other_ma.data.length < count

        # デバッグ出力
        if @debug_mode
          (1..count).each do |i|
            idx = @data.length - i
            if idx >= 0
              puts "MA比較[#{i}]: self=#{@data[idx]}, other=#{other_ma.data[idx]}, above?=#{@data[idx] > other_ma.data[idx]}"
            end
          end
        end

        (1..count).all? do |i|
          idx = @data.length - i
          idx >= 0 && @data[idx] > other_ma.data[idx]
        end
      end
      
      def below?(other_ma, count = 2)
        return false if @data.length < count || other_ma.data.length < count
        
        (1..count).all? do |i|
          idx = @data.length - i
          idx >= 0 && @data[idx] < other_ma.data[idx]
        end
      end
    end
  end
end
