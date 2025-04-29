require 'json'  # JSONライブラリを明示的にインポート

module MT4Backtester
  module Visualization
    class ChartDataProcessor

      def initialize(backtest_results, tick_data)
        @results = backtest_results
        @tick_data = tick_data
        @equity_curve = []
        @price_data = []
        @trade_points = []
        @indicator_data = backtest_results[:indicators] || {}
        
        process_data
      end
      
      attr_reader :equity_curve, :price_data, :trade_points, :results, :indicator_data
      
      def process_data
        # 価格データの準備（1時間ごとにサンプリング）
        process_price_data
        
        # 資産曲線の準備
        process_equity_curve
        
        # 取引ポイントの準備
        process_trade_points
        
        # インジケーターデータの処理
        process_indicator_data
      end

      def process_indicator_data
        # データが無い場合は何もしない
        return if @indicator_data.empty?
        
        # 各インジケーターのデータを時間でソート
        @indicator_data.each do |indicator_name, data_points|
          @indicator_data[indicator_name] = data_points.sort_by { |point| point[:time] }
        end
      end
      
      private
      
      def process_price_data
        return if @tick_data.empty?
        
        # 価格データを時間順にソート
        sorted_ticks = @tick_data.sort_by { |tick| tick[:time] }
        
        # 1時間ごとのOHLCデータを生成
        hour_samples = {}
        
        sorted_ticks.each do |tick|
          hour_key = tick[:time].strftime('%Y-%m-%d %H:00')
          
          if hour_samples[hour_key].nil?
            hour_samples[hour_key] = {
              time: hour_key,
              open: tick[:open],
              high: tick[:high],
              low: tick[:low],
              close: tick[:close],
              volume: tick[:volume]
            }
          else
            # 高値・安値の更新
            hour_samples[hour_key][:high] = [hour_samples[hour_key][:high], tick[:high]].max
            hour_samples[hour_key][:low] = [hour_samples[hour_key][:low], tick[:low]].min
            # 終値の更新
            hour_samples[hour_key][:close] = tick[:close]
            # 出来高の累積
            hour_samples[hour_key][:volume] += tick[:volume]
          end
        end
        
        # 時間順に並べ替えてデータ配列化
        @price_data = hour_samples.values.sort_by { |data| data[:time] }
      end
      
      def process_equity_curve
        return unless @results[:trades] && !@results[:trades].empty?
        
        initial_balance = @results[:params][:Start_Sikin] || 10000
        balance = initial_balance
        
        # 初期ポイント
        @equity_curve << {
          time: @tick_data.first[:time].strftime('%Y-%m-%d %H:%M'),
          balance: balance,
          equity: balance,
          drawdown: 0,
          margin: 0,
          free_margin: balance
        }
        
        # 各トレードの結果を反映
        max_balance = balance
        
        @results[:trades].each do |trade|
          # 取引後の残高更新
          balance += trade[:profit]
          
          # 最大残高の更新
          max_balance = balance if balance > max_balance
          
          # ドローダウンの計算
          drawdown = max_balance - balance
          
          # マージン情報（トレードに含まれていればそれを使用）
          margin = trade[:margin] || 0
          free_margin = balance - margin
          
          # エクイティカーブにポイント追加
          @equity_curve << {
            time: trade[:close_time].strftime('%Y-%m-%d %H:%M'),
            balance: balance,
            equity: balance,
            drawdown: drawdown,
            margin: margin,
            free_margin: free_margin
          }
        end
        
        # トレードがない場合は、最初と最後のティックだけデータポイント作成
        if @equity_curve.size <= 1 && !@tick_data.empty?
          @equity_curve << {
            time: @tick_data.last[:time].strftime('%Y-%m-%d %H:%M'),
            balance: initial_balance,
            equity: initial_balance,
            drawdown: 0,
            margin: 0,
            free_margin: initial_balance
          }
        end
      end
      

      def process_trade_points
        return unless @results[:trades] && !@results[:trades].empty?
        
        @results[:trades].each do |trade|
          # エントリーポイント
          entry_point = {
            time: trade[:open_time].strftime('%Y-%m-%d %H:%M'),
            price: trade[:open_price],
            type: trade[:type].to_s,
            action: 'entry',
            lot: trade[:lot_size],
            reason: trade[:reason] || "エントリー", # エントリー理由
            account_balance: trade[:entry_balance] || nil, # エントリー時の口座残高
            account_equity: trade[:entry_equity] || nil, # エントリー時のエクイティ
            margin: trade[:entry_margin] || nil, # エントリー時の必要証拠金
            positions_count: trade[:entry_positions_count] || nil # エントリー時のポジション数
          }
          
          # 決済ポイント
          exit_point = {
            time: trade[:close_time].strftime('%Y-%m-%d %H:%M'),
            price: trade[:close_price],
            type: trade[:type].to_s,
            action: 'exit',
            lot: trade[:lot_size],
            profit: trade[:profit],
            reason: trade[:exit_reason] || "決済", # 決済理由
            account_balance: trade[:exit_balance] || nil, # 決済後の口座残高
            account_equity: trade[:exit_equity] || nil, # 決済時のエクイティ
            margin: trade[:exit_margin] || nil, # 決済時の必要証拠金
            positions_count: trade[:exit_positions_count] || nil # 決済後のポジション数
          }
          
          @trade_points << entry_point
          @trade_points << exit_point
        end
        
        # 時間順にソート
        @trade_points.sort_by! { |point| point[:time] }
      end

    end
  end
end