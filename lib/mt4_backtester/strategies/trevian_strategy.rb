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
          margin: 0,
          free_margin: @params[:Start_Sikin] || 300
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
        
        # 取引情報に口座残高情報を追加
        enhance_trade_records
        
        @results
      end
      
      private
      
      def enhance_trade_records
        # 取引データがない場合は処理しない
        return unless @results[:trades] && !@results[:trades].empty?
        
        initial_balance = @params[:Start_Sikin] || 300
        running_balance = initial_balance
        
        @results[:trades].each_with_index do |trade, index|
          # エントリー情報の追加
          trade[:entry_balance] = running_balance
          trade[:entry_equity] = running_balance
          trade[:entry_margin] = calculate_margin(trade[:lot_size], trade[:open_price])
          trade[:entry_free_margin] = running_balance - trade[:entry_margin]
          
          # 決済後の残高計算
          running_balance += trade[:profit]
          
          # 決済情報の追加
          trade[:exit_balance] = running_balance
          trade[:exit_equity] = running_balance
          trade[:exit_margin] = 0  # 決済後はポジションがないので0
          trade[:exit_free_margin] = running_balance
          
          # トレード理由が設定されていない場合のデフォルト値
          if !trade[:reason] || trade[:reason].empty?
            trade[:reason] = get_default_entry_reason(trade)
          end
          
          if !trade[:exit_reason] || trade[:exit_reason].empty?
            trade[:exit_reason] = get_default_exit_reason(trade)
          end
          
          # 複数のトレードがある場合、相互に関連付け
          if index > 0
            prev_trade = @results[:trades][index - 1]
            trade[:previous_trade_profit] = prev_trade[:profit]
            
            # 連続したトレードの場合は理由を追加
            if (trade[:open_time] - prev_trade[:close_time]) < 300 # 5分以内に続いたトレード
              if prev_trade[:profit] < 0
                trade[:reason] = "#{trade[:reason]} (前回トレード: 損失 $#{prev_trade[:profit].round(2)})"
              else
                trade[:reason] = "#{trade[:reason]} (前回トレード: 利益 $#{prev_trade[:profit].round(2)})"
              end
            end
          end
        end
      end
      
      def calculate_margin(lot_size, price)
        # マージン計算のシンプルな例（実際にはもっと複雑）
        # 例: 1ロット = 100,000通貨単位、レバレッジ100倍の場合
        contract_size = 100000
        leverage = @params[:leverage] || 100
        
        (lot_size * contract_size * price) / leverage
      end
      
      def get_default_entry_reason(trade)
        type = trade[:type].to_s == "buy" ? "買い" : "売り"
        
        # MA値がある場合はそれを含める
        if @core_logic.indicator_calculator
          fast_ma = @core_logic.indicator_calculator.value(:fast_ma)
          slow_ma = @core_logic.indicator_calculator.value(:slow_ma)
          
          if fast_ma && slow_ma
            if trade[:type].to_s == "buy" && fast_ma > slow_ma
              return "MA(5)がMA(14)を上回ったため - 買い"
            elsif trade[:type].to_s == "sell" && fast_ma < slow_ma
              return "MA(5)がMA(14)を下回ったため - 売り"
            end
          end
        end
        
        "トレンド判断: #{type}"
      end
      
      def get_default_exit_reason(trade)
        profit = trade[:profit]
        
        if profit > 0
          # 利益確定
          return "利益確定 +$#{profit.round(2)}"
        elsif profit < -50
          # 大きな損失
          return "大きな損失 $#{profit.round(2)}"
        elsif profit < 0
          # 小さな損失
          return "損失 $#{profit.round(2)}"
        else
          # 損益ゼロ
          return "決済"
        end
      end
      
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
        required_margin = 0
        
        # コアロジックから現在のポジション情報を取得
        if @core_logic.respond_to?(:get_positions)
          positions = @core_logic.get_positions
          
          # ポジションがある場合、未確定損益と必要証拠金を計算
          positions.each do |pos|
            # 未確定損益（浮動利益）計算
            if pos[:type] == :buy
              open_positions_pnl += (tick[:close] - pos[:open_price]) * pos[:lot_size] * 100000
            else
              open_positions_pnl += (pos[:open_price] - tick[:close]) * pos[:lot_size] * 100000
            end
            
            # 必要証拠金計算
            required_margin += calculate_margin(pos[:lot_size], tick[:close])
          end
        end
        
        # アカウント残高更新
        @account[:equity] = @account[:balance] + open_positions_pnl
        @account[:margin] = required_margin
        @account[:free_margin] = @account[:equity] - @account[:margin]
      end
    end
  end
end