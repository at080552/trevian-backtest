module MT4Backtester
  module Indicators
    class Momentum
      attr_reader :data
      
      def initialize(period = 14, price_type = :close)
        @period = period
        @price_type = price_type
        @data = []
      end
      
      def calculate(price_data)
        @data = []
        
        return @data if price_data.length <= @period
        
        price_data.each_with_index do |candle, i|
          if i >= @period
            current = candle[@price_type]
            previous = price_data[i - @period][@price_type]
            @data << (current / previous) * 100
          else
            @data << nil
          end
        end
        
        @data
      end
      
      # 現在の値を取得するメソッドを追加
      def current_value
        @data.empty? ? nil : @data.last
      end
      
      # 前回の値を取得するメソッドを追加
      def previous_value
        @data.length < 2 ? nil : @data[-2]
      end
      
      def value(index)
        return nil if index >= @data.length || index < 0
        @data[index]
      end
    end
  end
end