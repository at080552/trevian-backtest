require_relative 'trevian/core_logic'

module MT4Backtester
  module Strategies
    class TrevianStrategy
      attr_reader :params, :results, :core_logic
      
      def initialize(params = {}, debug_mode = false)
        @params = params
        @debug_mode = debug_mode
        @core_logic = Trevian::CoreLogic.new(params, debug_mode)
        @results = nil
        @account = {
          balance: params[:Start_Sikin] || 300,
          equity: params[:Start_Sikin] || 300,
          margin: 0
        }
      end
      
      def run(tick_data)
        puts "Trevian戦略バックテストを実行中..."
        puts "パラメータ数: #{@params.size}"
        puts "ティックデータ数: #{tick_data.size}"
        
        # ティックデータを処理
        process_tick_data(tick_data)
        
        # 結果集計
        @results = @core_logic.get_results
        @results[:params] = @params
        
        @results
      end
      
      private
      
      def process_tick_data(tick_data)
        # テクニカル指標データの準備
        prepare_indicators(tick_data)
        
        # 各ティックを処理
        tick_data.each_with_index do |tick, index|
          # 10ティックごとにプログレス表示
          puts "ティック処理中: #{index}/#{tick_data.size}" if index % 1000 == 0 && index > 0
          
          # アカウント情報更新
          update_account(tick)
          
          # コアロジックに処理を委譲
          @core_logic.process_tick(tick, @account)
        end
      end
      
      def prepare_indicators(tick_data)
        # テクニカル指標計算
        # 例: 移動平均、モメンタム、その他Trevianで使われる指標
        
        # 実装は省略
        puts "テクニカル指標を計算中..."
      end
      
      def update_account(tick)
        # アカウント情報を更新
        # 実際のバックテストでは、各ティックごとに損益の計算が必要
        
        # 簡易実装
        open_positions_pnl = 0
        
        # アカウント残高更新
        @account[:equity] = @account[:balance] + open_positions_pnl
      end
    end
  end
end
