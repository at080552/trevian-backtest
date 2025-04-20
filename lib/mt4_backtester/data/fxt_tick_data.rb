module MT4Backtester
  module Data
    class FxtTickData < TickDataBase
      # MT4/MT5のFXTバイナリファイルから読み込む
      def load(file_path, options = {})
        raise "ファイルが存在しません: #{file_path}" unless File.exist?(file_path)
        
        # デフォルトオプション
        default_options = {
          version: 405,     # FXTファイルのバージョン（405 = MT4, 510 = MT5）
          header_size: 728  # ヘッダーサイズ（バイト）
        }
        
        # オプションのマージ
        opts = default_options.merge(options)
        
        puts "FXTファイルからティックデータを読み込んでいます: #{file_path}"
        
        begin
          @data = []
          
          # バイナリファイルを開く
          File.open(file_path, 'rb') do |file|
            # ヘッダーをスキップ
            file.seek(opts[:header_size])
            
            # MT4のFXTレコード構造
            # 4バイト: バー時間（UNIXタイムスタンプ）
            # 8バイト: 始値（double）
            # 8バイト: 高値（double）
            # 8バイト: 安値（double）
            # 8バイト: 終値（double）
            # 8バイト: 出来高（double）
            # 4バイト: スプレッド
            # 4バイト: リアルボリューム
            
            record_size = 52
            
            while !file.eof?
              record = file.read(record_size)
              break if record.nil? || record.size < record_size
              
              # バイナリデータをアンパック
              time, open, high, low, close, volume = record.unpack('LE8E8E8E8E8')
              
              # Timeオブジェクトに変換
              time = Time.at(time)
              
              tick = {
                time: time,
                open: open,
                high: high,
                low: low,
                close: close,
                volume: volume
              }
              
              @data << tick
            end
          end
          
          puts "#{@data.size}ティックの読み込みに成功しました。"
        rescue => e
          puts "FXT読み込み中にエラーが発生しました: #{e.message}"
          puts e.backtrace
          @data = []
        end
        
        @data
      end
    end
  end
end
