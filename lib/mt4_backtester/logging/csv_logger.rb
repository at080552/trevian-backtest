# lib/mt4_backtester/logging/csv_logger.rb を作成
module MT4Backtester
  module Logging
    class CsvLogger
      def initialize(file_path)
        @file_path = file_path
        @file = nil
        @headers = ['date', 'time', 'price', 'ma5', 'ma14', 'positions', 'close_flag', 'trailing_stop_flag', 'balance']
      end
      
      def open
        # ディレクトリがなければ作成
        dir = File.dirname(@file_path)
        FileUtils.mkdir_p(dir) unless File.directory?(dir)
        
        @file = File.open(@file_path, 'w')
        # ヘッダー行を書き込む
        @file.puts @headers.join(',')
      end
      
      def close
        @file.close if @file
      end
      
      def log(tick, indicators, state, account)
        return unless @file
        
        # 日付と時間を分割
        datetime = tick[:time]
        date = datetime.strftime('%Y-%m-%d')
        time = datetime.strftime('%H:%M:%S')
        
        # MA値を取得
        ma5 = indicators[:fast_ma] || 0
        ma14 = indicators[:slow_ma] || 0
        
        # 状態情報
        positions = state[:all_position] || 0
        close_flag = state[:close_flag] || 0
        trailing_stop_flag = state[:trailing_stop_flag] || 0
        
        # 残高情報
        balance = account[:balance] || 0
        
        # CSV行を作成
        row = [
          date,
          time,
          tick[:close],
          ma5,
          ma14,
          positions,
          close_flag,
          trailing_stop_flag,
          balance
        ]
        
        # CSVに書き込み
        @file.puts row.join(',')
        @file.flush  # すぐに書き込みを反映
      end
    end
  end
end