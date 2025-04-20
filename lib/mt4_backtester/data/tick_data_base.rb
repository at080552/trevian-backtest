module MT4Backtester
  module Data
    class TickDataBase
      attr_reader :data, :symbol, :timeframe
      
      def initialize(symbol = 'GBPUSD', timeframe = :M1)
        @symbol = symbol
        @timeframe = timeframe
        @data = []
      end
      
      # データのフィルタリング
      def filter_by_date(start_date, end_date)
        @data.select do |tick|
          tick[:time] >= start_date && tick[:time] <= end_date
        end
      end
      
      # データの基本統計
      def statistics
        return {} if @data.empty?
        
        prices = @data.map { |tick| tick[:close] }
        {
          count: @data.size,
          start_time: @data.first[:time],
          end_time: @data.last[:time],
          min_price: prices.min,
          max_price: prices.max,
          avg_price: prices.sum / prices.size
        }
      end
      
      # データの表示
      def print_summary
        stats = statistics
        return puts "データがありません" if stats.empty?
        
        puts "===== ティックデータサマリー ====="
        puts "通貨ペア: #{@symbol}"
        puts "時間枠: #{@timeframe}"
        puts "データ数: #{stats[:count]}"
        puts "期間: #{stats[:start_time]} から #{stats[:end_time]}"
        puts "価格範囲: #{stats[:min_price]} - #{stats[:max_price]}"
        puts "平均価格: #{stats[:avg_price]}"
        puts "=================================="
      end
    end
  end
end
