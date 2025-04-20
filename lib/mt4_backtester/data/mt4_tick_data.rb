require 'csv'
require 'time'

module MT4Backtester
  module Data
    class MT4TickData < TickDataBase
      # MT4の本番ティックデータ形式を読み込む
      def load(file_path, options = {})
        raise "ファイルが存在しません: #{file_path}" unless File.exist?(file_path)
        
        # デフォルトオプション
        default_options = {
          has_header: false,
          delimiter: ',',
          date_format: '%Y%m%d %H%M%S%L'
        }
        
        # オプションのマージ
        opts = default_options.merge(options)
        
        puts "MT4ティックデータを読み込んでいます: #{file_path}"
        
        begin
          @data = []
          
          # ファイルを読み込み
          lines = File.readlines(file_path)
          
          # ヘッダー行をスキップ
          lines.shift if opts[:has_header]
          
          lines.each do |line|
            # カンマで分割
            fields = line.strip.split(opts[:delimiter])
            
            # フィールドが足りない場合はスキップ
            next if fields.size < 3
            
            # タイムスタンプ、Bid、Ask、ボリュームを抽出
            timestamp = fields[0]
            bid = fields[1].to_f
            ask = fields[2].to_f
            volume = fields[3].to_f if fields.size > 3
            
            # 時間をパース
            begin
              time = Time.strptime(timestamp, opts[:date_format])
            rescue => e
              puts "時間解析エラー: #{e.message} - #{timestamp}"
              next
            end
            
            # データポイントを生成
            tick = {
              time: time,
              open: bid,  # BidをOHLCに変換
              high: bid,
              low: bid,
              close: bid,
              ask: ask,
              spread: (ask - bid) * 10000, # スプレッドをpips単位で計算
              volume: volume || 0
            }
            
            @data << tick
          end
          
          # データを時間順にソート
          @data.sort_by! { |tick| tick[:time] }
          
          # 詳細を表示
          if @data.any?
            min_time = @data.first[:time]
            max_time = @data.last[:time]
            
            puts "#{@data.size}ティックの読み込みに成功しました。"
            puts "期間: #{min_time} から #{max_time}"
            puts "最初のティック: Bid=#{@data.first[:open]}, Ask=#{@data.first[:ask]}, Spread=#{@data.first[:spread]}pips"
            puts "最後のティック: Bid=#{@data.last[:open]}, Ask=#{@data.last[:ask]}, Spread=#{@data.last[:spread]}pips"
          else
            puts "データが読み込めませんでした。"
          end
          
        rescue => e
          puts "ティックデータ読み込み中にエラーが発生しました: #{e.message}"
          puts e.backtrace
          @data = []
        end
        
        # OHLCデータに変換（1分足）
        convert_to_ohlc(60) if @data.any?
        
        @data
      end
      
      # ティックデータをOHLCデータに変換（時間枠は秒単位）
      def convert_to_ohlc(timeframe = 60)
        return if @data.empty?
        
        # 時間枠ごとにデータをグループ化
        ohlc_data = {}
        
        @data.each do |tick|
          # 時間を切り捨て（例：1分足なら秒を切り捨て）
          time_key = Time.at((tick[:time].to_i / timeframe).floor * timeframe)
          
          if ohlc_data[time_key].nil?
            ohlc_data[time_key] = {
              time: time_key,
              open: tick[:open],
              high: tick[:open],
              low: tick[:open],
              close: tick[:open],
              volume: tick[:volume]
            }
          else
            # 高値・安値の更新
            ohlc_data[time_key][:high] = [ohlc_data[time_key][:high], tick[:open]].max
            ohlc_data[time_key][:low] = [ohlc_data[time_key][:low], tick[:open]].min
            # 終値の更新
            ohlc_data[time_key][:close] = tick[:open]
            # 出来高の累積
            ohlc_data[time_key][:volume] += tick[:volume]
          end
        end
        
        # 時間順にソートして配列に変換
        @data = ohlc_data.values.sort_by { |candle| candle[:time] }
        
        puts "#{@data.size}個のOHLCデータに変換しました（時間枠: #{timeframe}秒）"
      end
    end
  end
end
