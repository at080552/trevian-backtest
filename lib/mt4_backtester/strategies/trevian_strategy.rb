require_relative 'trevian/core_logic'

module MT4Backtester
  module Strategies
    class TrevianStrategy
      attr_reader :params, :results, :core_logic, :indicators_data

      def initialize(params = {}, debug_mode = false)
        # 環境変数から設定を読み込む
        env_params = MT4Backtester::Config::ConfigLoader.load
          
        # パラメータをマージ（ユーザー指定のパラメータを優先）
        @params = env_params.merge(params)
          
        @debug_mode = debug_mode
        @core_logic = Trevian::CoreLogic.new(@params, debug_mode)
        @results = nil
        @account = {
          balance: @params[:Start_Sikin] || 300,
          equity: @params[:Start_Sikin] || 300,
          margin: 0
          }
        @indicators_data = {
          ma_fast: [],
          ma_slow: [],
          momentum: []
          }
      end

      def get_indicators_data
        @indicators_data
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
          # 指標データの記録（1時間ごとなど、適切な間隔で）
          if index % 60 == 0 || index == tick_data.size - 1
            record_indicator_data(tick, index)
          end

          # アカウント情報更新
          update_account(tick)
          
          # コアロジックに処理を委譲
          @core_logic.process_tick(tick, @account)
        end
      end

      def record_indicator_data(tick, index)
        # インジケーターが初期化されているか確認
        return unless @core_logic && @core_logic.respond_to?(:indicator_calculator) && @core_logic.indicator_calculator
        
        # インジケーターの値を取得
        begin
          fast_ma = @core_logic.indicator_calculator.value(:fast_ma)
          slow_ma = @core_logic.indicator_calculator.value(:slow_ma)
          
          # モメンタム値を取得（エラー処理付き）
          momentum_value = nil
          if @core_logic.indicator_calculator.indicators && 
             @core_logic.indicator_calculator.indicators[:momentum]
            momentum_indicator = @core_logic.indicator_calculator.indicators[:momentum]
            
            if momentum_indicator.respond_to?(:current_value)
              momentum_value = momentum_indicator.current_value
            elsif momentum_indicator.respond_to?(:data) && !momentum_indicator.data.empty?
              momentum_value = momentum_indicator.data.last
            end
          end
          
          # データを記録
          @indicators_data[:ma_fast] << {
            time: tick[:time],
            value: fast_ma
          } if fast_ma
          
          @indicators_data[:ma_slow] << {
            time: tick[:time],
            value: slow_ma
          } if slow_ma
          
          @indicators_data[:momentum] << {
            time: tick[:time],
            value: momentum_value
          } if momentum_value
          
        rescue => e
          puts "インジケーターデータの記録中にエラーが発生しました: #{e.message}" if @debug_mode
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
