require 'csv'
require 'time'
require 'zlib'

module MT4Backtester
  module Data
    class HistdataTickData < TickDataBase
      # HistData.comのCSVファイルから読み込む（ZIP/GZ圧縮対応）
      def load(file_path, options = {})
        raise "ファイルが存在しません: #{file_path}" unless File.exist?(file_path)
        
        # デフォルトオプション
        default_options = {
          format: :auto,  # auto, tick, m1, specific, mt4tick
          has_header: false, # ヘッダー行の有無
          date_format: '%Y.%m.%d', # 日付フォーマット
          delimiter: ',', # 区切り文字
          timezone_offset: 0, # タイムゾーン調整（時間単位）
          convert_to_jst: false # 日本時間への変換フラグ
        }
        
        # オプションのマージ
        opts = default_options.merge(options)
        
        # 日本時間への変換フラグが設定されている場合
        if opts[:convert_to_jst]
          # HistDataはEST（UTC-5）固定なので、日本時間（UTC+9）への変換は+14時間
          opts[:timezone_offset] = 14
        end
        
        puts "HistData.comのデータを読み込んでいます: #{file_path}"
        if opts[:timezone_offset] != 0
          puts "タイムゾーン調整: #{opts[:timezone_offset]}時間"
        end
        
        begin
          @data = []
          
          # 圧縮ファイルの処理
          data_content = nil
          
          if file_path.end_with?('.gz')
            data_content = Zlib::GzipReader.open(file_path) { |gz| gz.read }
          elsif file_path.end_with?('.zip')
            require 'zip'
            Zip::File.open(file_path) do |zip_file|
              entry = zip_file.glob('*.csv').first
              data_content = entry.get_input_stream.read if entry
            end
          else
            data_content = File.read(file_path)
          end
          
          raise "データを読み込めませんでした" unless data_content
          
          # ファイルの先頭行をチェックしてフォーマットを自動検出
          if opts[:format] == :auto
            first_lines = data_content.split("\n")[0..5]
            first_line = first_lines.first.strip
            
            # ヘッダー行の検出
            if first_line.include?('Symbol') || first_line.include?('SYMBOL') || first_line.include?('Date')
              opts[:has_header] = true
            end
            
            # MT4ティックデータフォーマットの検出
            if first_line =~ /^\d{8}\s\d{9}\s\d+\.\d+/ || first_line =~ /^\d{8}\s\d+\s\d+\.\d+/
              opts[:format] = :mt4tick
              opts[:delimiter] = ' '
            elsif first_line.count(',') == 6  # OHLCV形式
              opts[:format] = :m1
            elsif first_line.count(',') == 4  # Bid/Ask形式
              opts[:format] = :tick
            elsif first_line =~ /^\d{4}\.\d{2}\.\d{2},\d{2}:\d{2},/
              # HistDataの独自フォーマット検出
              opts[:format] = :specific
            end
          end
          
          # データの解析
          lines = data_content.split("\n")
          if opts[:has_header]
            lines.shift  # ヘッダー行をスキップ
          end
          
          lines.each do |line|
            # 空行をスキップ
            next if line.strip.empty?
            
            case opts[:format]
            when :mt4tick
              # MT4ティックデータフォーマット (YYYYMMDD HHMMSSMMM PRICE)
              fields = line.strip.split(/\s+/)
              
              next if fields.size < 3
              
              date_str = fields[0]
              time_str = fields[1]
              price = fields[2].to_f
              
              # 日付と時間を結合
              datetime_str = "#{date_str} #{time_str}"
              
              begin
                tick_time = Time.strptime(datetime_str, '%Y%m%d %H%M%S%L')
                # タイムゾーン調整
                tick_time += opts[:timezone_offset] * 3600 if opts[:timezone_offset] != 0
              rescue => e
                puts "時間解析エラー: #{e.message} - #{datetime_str}"
                next
              end
              
              tick = {
                time: tick_time,
                open: price,
                high: price,
                low: price,
                close: price,
                volume: 0
              }
              
              @data << tick
            when :tick
              # HistData.comのTick Data Format (SYMBOL,YYYYMMDD,HHMMSS,BID,ASK)
              fields = line.split(opts[:delimiter])
              
              next if fields.size < 4
              
              # フィールドの解析方法はファイル構造によって異なる
              symbol, date, time, bid, ask = fields
              
              if date.nil? || time.nil?
                next
              end
              
              # 日付と時間を結合
              datetime_str = "#{date} #{time}"
              
              begin
                tick_time = Time.strptime(datetime_str, '%Y%m%d %H%M%S%L')
                # タイムゾーン調整
                tick_time += opts[:timezone_offset] * 3600 if opts[:timezone_offset] != 0
              rescue => e
                puts "時間解析エラー: #{e.message} - #{datetime_str}"
                next
              end
              
              tick = {
                time: tick_time,
                open: bid.to_f,
                high: bid.to_f,
                low: bid.to_f,
                close: bid.to_f,
                ask: ask.to_f,
                volume: 0  # TickデータにはVolumeがない
              }
              
              @data << tick
            when :m1
              # HistData.comのM1 Data Format (YYYYMMDD,HHMM,OPEN,HIGH,LOW,CLOSE,VOLUME)
              fields = line.split(opts[:delimiter])
              
              next if fields.size < 6
              
              date, time, open, high, low, close, volume = fields
              
              # 日付と時間を結合
              datetime_str = "#{date} #{time}"
              
              begin
                tick_time = Time.strptime(datetime_str, "#{opts[:date_format]} %H:%M")
                # タイムゾーン調整
                tick_time += opts[:timezone_offset] * 3600 if opts[:timezone_offset] != 0
              rescue => e
                puts "時間解析エラー: #{e.message} - #{datetime_str}"
                next
              end
              
              tick = {
                time: tick_time,
                open: open.to_f,
                high: high.to_f,
                low: low.to_f,
                close: close.to_f,
                volume: volume.to_f
              }
              
              @data << tick
            when :specific
              # 特定のフォーマット（例：2025.03.02,17:01,1.258000,1.258000,1.258000,1.258000,0）
              fields = line.split(opts[:delimiter])
              
              next if fields.size < 5
              
              date, time, open, high, low, close, volume = fields
              
              # 日付と時間を結合
              datetime_str = "#{date} #{time}"
              
              begin
                tick_time = Time.strptime(datetime_str, "#{opts[:date_format]} %H:%M")
                # タイムゾーン調整
                tick_time += opts[:timezone_offset] * 3600 if opts[:timezone_offset] != 0
              rescue => e
                puts "時間解析エラー: #{e.message} - #{datetime_str} - #{opts[:date_format]}"
                next
              end
              
              tick = {
                time: tick_time,
                open: open.to_f,
                high: high.to_f,
                low: low.to_f,
                close: close.to_f,
                volume: volume.to_f
              }
              
              @data << tick
            else
              # 一般的なCSV形式として処理
              fields = line.split(opts[:delimiter])
              
              next if fields.size < 3
              
              # 最低限必要なフィールド数であれば処理を試みる
              # 様々な形式に対応
              if fields.size >= 3 && fields[0] =~ /^\d+/ && fields[2] =~ /^\d+\.\d+/
                # MT4ティックデータ形式の可能性
                date_str = fields[0]
                time_str = fields[1]
                price = fields[2].to_f
                
                # 日付と時間を結合
                datetime_str = "#{date_str} #{time_str}"
                
                begin
                  tick_time = Time.strptime(datetime_str, '%Y%m%d %H%M%S%L')
                  # タイムゾーン調整
                  tick_time += opts[:timezone_offset] * 3600 if opts[:timezone_offset] != 0
                rescue => e
                  # 別の形式を試す
                  begin
                    tick_time = Time.parse(datetime_str)
                    # タイムゾーン調整
                    tick_time += opts[:timezone_offset] * 3600 if opts[:timezone_offset] != 0
                  rescue => e2
                    puts "時間解析エラー: #{e2.message} - #{datetime_str}"
                    next
                  end
                end
                
                tick = {
                  time: tick_time,
                  open: price,
                  high: price,
                  low: price,
                  close: price,
                  volume: 0
                }
                
                @data << tick
              else
                # その他の形式は適切に解析を試みる
                # ...
              end
            end
          end
          
          # 時間順にソート
          @data.sort_by! { |tick| tick[:time] }
          
          puts "#{@data.size}ティックの読み込みに成功しました。"
          if @data.size > 0
            puts "データ範囲: #{@data.first[:time]} から #{@data.last[:time]}"
          end
        rescue => e
          puts "HistData読み込み中にエラーが発生しました: #{e.message}"
          puts e.backtrace
          @data = []
        end
        
        @data
      end
    end
  end
end