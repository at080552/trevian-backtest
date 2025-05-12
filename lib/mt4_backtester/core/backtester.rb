module MT4Backtester
  module Core
    class Backtester
      attr_reader :results, :strategy, :tick_data
      attr_accessor :logger_path
      
      def initialize(strategy, tick_data)
        @strategy = strategy
        @tick_data = tick_data
        @results = nil
        @logger_path = nil  # ロガーの出力先パス
      end
      
      def run
        puts "バックテスト実行開始"
        puts "ティックデータ数: #{@tick_data.size}"

        # ロガーの設定（パスが指定されている場合）
        if @logger_path && @strategy.respond_to?(:core_logic) && @strategy.core_logic.respond_to?(:logger=)
          require_relative '../logging/csv_logger'
          logger = MT4Backtester::Logging::CsvLogger.new(@logger_path)
          logger.open
          @strategy.core_logic.logger = logger
          puts "ログ出力を有効化: #{@logger_path}"
        end

        start_time = Time.now
        
        # 戦略を実行
        @results = @strategy.run(@tick_data)
        # テクニカル指標データの追加
        @results[:indicators] = @strategy.get_indicators_data if @strategy.respond_to?(:get_indicators_data)
        
        end_time = Time.now
        puts "バックテスト実行時間: #{(end_time - start_time).round(2)}秒"

        # ロガーを閉じる
        if @strategy.respond_to?(:core_logic) && @strategy.core_logic.respond_to?(:logger) && @strategy.core_logic.logger
          @strategy.core_logic.logger.close
        end

        # 戦略の結果を後処理
        post_process_results
        
        @results
      end
      
      private
      
      def post_process_results
        return unless @results
        
        # 通貨単位情報
        @results[:currency] = "USD"  # 基本通貨単位
        @results[:account_currency] = "JPY"  # 口座通貨単位
        
        # 為替レートを戦略オブジェクトから取得（戦略が持つパラメータを参照）
        if @strategy.respond_to?(:params) && @strategy.params && @strategy.params[:USDJPY_rate]
          @results[:exchange_rate] = @strategy.params[:USDJPY_rate]
        else
          # デフォルト値を設定（推奨）
          @results[:exchange_rate] = 155.0  # デフォルトUSD/JPYレート
        end
        
        # トレード統計の追加計算
        calculate_trade_statistics
        
        # エクイティカーブの計算
        calculate_equity_curve
      end
      
      def calculate_trade_statistics
        return unless @results[:trades] && !@results[:trades].empty?
        
        # 勝率計算
        winning_trades = @results[:trades].count { |t| t[:profit] > 0 }
        total_trades = @results[:trades].size
        
        @results[:win_rate] = total_trades > 0 ? winning_trades.to_f / total_trades : 0
        
        # 平均利益と平均損失
        profits = @results[:trades].select { |t| t[:profit] > 0 }.map { |t| t[:profit] }
        losses = @results[:trades].select { |t| t[:profit] <= 0 }.map { |t| t[:profit] }
        
        @results[:avg_profit] = profits.empty? ? 0 : profits.sum / profits.size
        @results[:avg_loss] = losses.empty? ? 0 : losses.sum / losses.size
        
        # プロフィットファクター
        gross_profit = profits.sum
        gross_loss = losses.sum.abs
        
        @results[:profit_factor] = gross_loss > 0 ? gross_profit / gross_loss : (gross_profit > 0 ? Float::INFINITY : 0)
        
        # 期待値
        @results[:expected_payoff] = total_trades > 0 ? @results[:total_profit] / total_trades : 0
      end
      
      def calculate_equity_curve
        return unless @results[:trades] && !@results[:trades].empty?
        
        # エクイティカーブの計算
        equity_curve = []
        balance = @strategy.params[:Start_Sikin] || 10000
        
        @results[:trades].each do |trade|
          balance += trade[:profit]
          equity_curve << {
            time: trade[:close_time],
            balance: balance,
            trade_profit: trade[:profit]
          }
        end
        
        @results[:equity_curve] = equity_curve
      end
    end
  end
end
