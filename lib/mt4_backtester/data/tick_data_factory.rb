module MT4Backtester
  module Data
    class TickDataFactory
      # ファイル拡張子に基づいて適切なデータローダーを選択
      def self.create_loader(file_path, symbol = nil, timeframe = nil)
        ext = File.extname(file_path).downcase
        
        # ファイル名からシンボルと時間枠を推測
        if symbol.nil? || timeframe.nil?
          basename = File.basename(file_path, ext)
          parts = basename.split('_')
          
          symbol ||= parts[0] if parts[0] =~ /[A-Z]{6}/
          
          # 時間枠を推測
          if timeframe.nil? && parts.size > 1
            timeframe_str = parts[-1]
            timeframe = case timeframe_str.downcase
                        when 'm1', '1m' then :M1
                        when 'm5', '5m' then :M5
                        when 'm15', '15m' then :M15
                        when 'm30', '30m' then :M30
                        when 'h1', '1h' then :H1
                        when 'h4', '4h' then :H4
                        when 'd1', '1d' then :D1
                        when 'w1', '1w' then :W1
                        when 'mn', '1mn' then :MN
                        else :M1
                        end
          end
        end
        
        # デフォルト値
        symbol ||= 'GBPUSD'
        timeframe ||= :M1
        
        # ファイル内容をチェックして形式を判断（先頭数行を読み込む）
        # File.readlines に第二引数を渡すと行区切り文字として扱われて
        # しまい、意図した "最初の10行" を取得できないバグがあった。
        # そのため first(10) を用いて明示的に先頭10行だけを取得する。
        first_lines = File.readlines(file_path).first(10).map(&:strip)
        
        # MT4ティックデータ形式かどうかを判断
        if first_lines.any? && first_lines[0] =~ /^\d{8}\s\d{9},\d+\.\d+,\d+\.\d+/
          return MT4TickData.new(symbol, timeframe)
        end
        
        # ファイル形式に基づいてローダーを選択
        case ext
        when '.csv'
          CsvTickData.new(symbol, timeframe)
        when '.fxt'
          FxtTickData.new(symbol, timeframe)
        when '.gz', '.zip'
          if file_path.include?('histdata')
            HistdataTickData.new(symbol, timeframe)
          else
            # 圧縮ファイルを解凍して内部を確認
            CsvTickData.new(symbol, timeframe)
          end
        else
          # デフォルトはCSV
          CsvTickData.new(symbol, timeframe)
        end
      end
    end
  end
end
