require 'csv'
require 'time'

module MT4Backtester
  module Data
    class CsvTickData < TickDataBase
      # CSVファイルからティックデータを読み込む
      def load(file_path, options = {})
        raise "ファイルが存在しません: #{file_path}" unless File.exist?(file_path)
        
        # デフォルトオプション
        default_options = {
          headers: true,               # ヘッダー行あり
          time_column: 'time',         # 時間列の名前
          open_column: 'open',         # 始値列の名前
          high_column: 'high',         # 高値列の名前
          low_column: 'low',           # 安値列の名前
          close_column: 'close',       # 終値列の名前
          volume_column: 'volume',     # 出来高列の名前
          time_format: '%Y-%m-%d %H:%M:%S', # 時間のフォーマット
          skip_lines: 0,               # スキップする行数
          delimiter: ','               # 区切り文字
        }
        
        # オプションのマージ
        opts = default_options.merge(options)
        
        puts "CSVファイルからティックデータを読み込んでいます: #{file_path}"
        
        # CSVファイルを読み込む
        begin
          @data = []
          csv_data = File.read(file_path)
          csv = CSV.parse(csv_data, headers: opts[:headers], col_sep: opts[:delimiter])
          
          # ヘッダー行をスキップ
          opts[:skip_lines].times { csv.shift } if opts[:headers]
          
          # 各行を処理
          csv.each do |row|
            # 時間の解析
            time_str = row[opts[:time_column]]
            
            # 時間の解析方法が異なる場合の対応
            time = begin
              if opts[:time_format] == :unix
                Time.at(time_str.to_i)
              elsif opts[:time_format] == :excel
                # Excelの日付形式（1900年1月1日からの日数）
                base_date = Time.new(1900, 1, 1)
                base_date + (time_str.to_f - 2) * 24 * 60 * 60 # 2日の調整（Excelのバグ）
              else
                Time.strptime(time_str, opts[:time_format])
              end
            rescue => e
              puts "時間の解析でエラーが発生しました: #{time_str} - #{e.message}"
              next
            end
            
            # データポイントの作成
            tick = {
              time: time,
              open: row[opts[:open_column]].to_f,
              high: row[opts[:high_column]].to_f,
              low: row[opts[:low_column]].to_f,
              close: row[opts[:close_column]].to_f,
              volume: row[opts[:volume_column]].to_f
            }
            
            @data << tick
          end
          
          # 時間順にソート
          @data.sort_by! { |tick| tick[:time] }
          
          puts "#{@data.size}ティックの読み込みに成功しました。"
        rescue => e
          puts "CSV読み込み中にエラーが発生しました: #{e.message}"
          puts e.backtrace
          @data = []
        end
        
        @data
      end
    end
  end
end
