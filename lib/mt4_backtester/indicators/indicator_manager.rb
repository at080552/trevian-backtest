module MT4Backtester
  module Indicators
    class IndicatorManager
      def initialize
        @indicators = {}
        @candles = []
      end
      
      def add_indicator(name, indicator)
        @indicators[name] = indicator
      end
      
      def get_indicator(name)
        @indicators[name]
      end
      
      def update_candles(candles)
        @candles = candles
        recalculate_all
      end
      
      def recalculate_all
        @indicators.each do |name, indicator|
          indicator.calculate(@candles)
        end
      end
      
      def value(name, index)
        indicator = @indicators[name]
        return nil unless indicator
        
        indicator.value(index)
      end
    end
  end
end
