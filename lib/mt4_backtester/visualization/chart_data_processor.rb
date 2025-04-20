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
        
        process_data
      end
      
      attr_reader :equity_curve, :price_data, :trade_points, :results
      
      def process_data
        # 価格データの準備（1時間ごとにサンプリング）
        process_price_data
        
        # 資産曲線の準備
        process_equity_curve
        
        # 取引ポイントの準備
        process_trade_points
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
          drawdown: 0
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
          
          # エクイティカーブにポイント追加
          @equity_curve << {
            time: trade[:close_time].strftime('%Y-%m-%d %H:%M'),
            balance: balance,
            equity: balance,
            drawdown: drawdown
          }
        end
        
        # トレードがない場合は、最初と最後のティックだけデータポイント作成
        if @equity_curve.size <= 1 && !@tick_data.empty?
          @equity_curve << {
            time: @tick_data.last[:time].strftime('%Y-%m-%d %H:%M'),
            balance: initial_balance,
            equity: initial_balance,
            drawdown: 0
          }
        end
      end
      
      def process_trade_points
        return unless @results[:trades] && !@results[:trades].empty?
        
        @results[:trades].each do |trade|
          # エントリーポイント
          @trade_points << {
            time: trade[:open_time].strftime('%Y-%m-%d %H:%M'),
            price: trade[:open_price],
            type: trade[:type].to_s,
            action: 'entry',
            lot: trade[:lot_size]
          }
          
          # 決済ポイント
          @trade_points << {
            time: trade[:close_time].strftime('%Y-%m-%d %H:%M'),
            price: trade[:close_price],
            type: trade[:type].to_s,
            action: 'exit',
            lot: trade[:lot_size],
            profit: trade[:profit]
          }
        end
        
        # 時間順にソート
        @trade_points.sort_by! { |point| point[:time] }
      end
    end
  end
end
