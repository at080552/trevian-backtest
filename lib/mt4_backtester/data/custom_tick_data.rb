require 'csv'
require 'time'

module MT4Backtester
  module Data
    class CustomTickData < TickDataBase
      # カスタムティックデータ形式を読み込む
      def load(file_path, options = {})
        raise "ファイルが存在しません: #{file_path}" unless File.exist?(file_path)
        
        # デフォルトオプション
        default_options = {
          has_header: false
        }
        
        # オプションのマージ
        opts = default_options.merge(options)
        
        puts "カスタムティックデータを読み込んでいます: #{file_path}"
        
        begin
          @data = []
          
          # ファイルを読み込み
          lines = File.readlines(file_path)
          
          # ヘッダー行をスキップ
          lines.shift if opts[:has_header]
          
          lines.each do |line|
            # 最初のスペースと残りのカンマで分割
            parts = line.strip.split(' ', 2)
            
            next if parts.size < 2
            
            date_str = parts[0]
            
            # 残りの部分をカンマで分割
            rest_parts = parts[1].split(',')
            
            next if rest_parts.size < 3
            
            time_str = rest_parts[0]
            bid = rest_parts[1].to_f
            ask = rest_parts[2].to_f
            
            # 日付と時間を解析
            begin
              # 時間部分にミリ秒が含まれているのでそれを処理
              datetime_str = "#{date_str} #{time_str}"
              tick_time = Time.strptime(datetime_str, '%Y%m%d %H%M%S%L')
            rescue => e
              puts "時間解析エラー: #{e.message} - #{datetime_str}"
              next
            end
            
            # ティックデータを作成
            tick = {
              time: tick_time,
              open: bid,
              high: bid,
              low: bid,
              close: bid,
              ask: ask,
              spread: (ask - bid) * 10000, # スプレッドをpips単位で計算
              volume: rest_parts[3].to_f # ボリュームがあれば
            }
            
            @data << tick
          end
          
          # 時間順にソート
          @data.sort_by! { |tick| tick[:time] }
          
          # OHLC形式に変換（1分足）
          convert_to_ohlc_data
          
          # 詳細を表示
          if @data.any?
            min_time = @data.first[:time]
            max_time = @data.last[:time]
            
            puts "#{@data.size}ティックの読み込みに成功しました。"
            puts "期間: #{min_time} から #{max_time}"
            puts "最初のティック: Open=#{@data.first[:open]}, High=#{@data.first[:high]}, Low=#{@data.first[:low]}, Close=#{@data.first[:close]}"
            puts "最後のティック: Open=#{@data.last[:open]}, High=#{@data.last[:high]}, Low=#{@data.last[:low]}, Close=#{@data.last[:close]}"
          else
            puts "データが読み込めませんでした。"
          end
          
        rescue => e
          puts "ティックデータ読み込み中にエラーが発生しました: #{e.message}"
          puts e.backtrace
          @data = []
        end
        
        @data
      end
      
      # ティックデータをOHLCデータに変換（1分足）
      def convert_to_ohlc_data
        return if @data.empty?
        
        # 1分ごとにグループ化
        ohlc_data = {}
        
        @data.each do |tick|
          # 分単位で切り捨て
          minute_key = Time.new(
            tick[:time].year,
            tick[:time].month,
            tick[:time].day,
            tick[:time].hour,
            tick[:time].min,
            0
          )
          
          if ohlc_data[minute_key].nil?
            ohlc_data[minute_key] = {
              time: minute_key,
              open: tick[:open],
              high: tick[:open],
              low: tick[:open],
              close: tick[:open],
              volume: tick[:volume]
            }
          else
            # 高値・安値の更新
            ohlc_data[minute_key][:high] = [ohlc_data[minute_key][:high], tick[:open]].max
            ohlc_data[minute_key][:low] = [ohlc_data[minute_key][:low], tick[:open]].min
            # 終値の更新
            ohlc_data[minute_key][:close] = tick[:open]
            # 出来高の累積
            ohlc_data[minute_key][:volume] += tick[:volume]
          end
        end
        
        # 時間順にソートして配列に変換
        @data = ohlc_data.values.sort_by { |candle| candle[:time] }
        
        puts "#{@data.size}個のOHLCデータに変換しました（時間枠: 1分）"
      end
    end
  end
end
