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
          initial_balance: @params[:Start_Sikin] || 300,
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
        
        # ポジション管理の初期化（通貨ペアごとに管理）
        active_positions = {}
        
        # 時間順にソート（念のため）
        @results[:trades].sort_by! { |t| t[:open_time] }
        
        @results[:trades].each_with_index do |trade, index|
          symbol = trade[:symbol] || 'GBPUSD' # シンボルがなければデフォルト値

    # 通貨単位を明示的に設定
    trade[:currency] = "JPY"
    trade[:balance_currency] = "JPY"

    # JPY換算の利益も記録（存在しない場合）
    if !trade[:profit_jpy] && trade[:profit]
      trade[:profit_jpy] = trade[:profit] * @params[:USDJPY_rate]
    end

    # 小数点以下の精度を統一（丸め誤差を防止）
    trade[:profit] = trade[:profit].round(5) if trade[:profit]
    trade[:profit_jpy] = trade[:profit_jpy].round(2) if trade[:profit_jpy]

          # 通貨ペアごとのポジション管理
          active_positions[symbol] ||= []
          
          # エントリー前のポジション数を記録
          trade[:entry_positions_count] = active_positions[symbol].size
          
          # ポジションリストに追加
          position_info = {
            id: trade[:ticket] || "pos_#{index}",
            type: trade[:type],
            lot: trade[:lot_size],
            open_time: trade[:open_time],
            open_price: trade[:open_price]
          }
          active_positions[symbol] << position_info
          
          # エントリー後のポジション数を更新（自分自身を含む）
          trade[:entry_positions_count_after] = active_positions[symbol].size
          
          # エントリー情報の追加
          trade[:entry_balance] = running_balance
          trade[:entry_equity] = running_balance
          trade[:entry_margin] = calculate_margin(trade[:lot_size], trade[:open_price])
          trade[:entry_free_margin] = running_balance - trade[:entry_margin]

          # 決済後の残高計算
          running_balance += (trade[:profit_jpy] || trade[:profit] * @params[:USDJPY_rate])
          
          # 決済時のポジション管理（自分を除外）
          # このトレードを見つけて除外
          active_positions[symbol].reject! { |p| 
            p[:id] == (trade[:ticket] || "pos_#{index}") && 
            p[:open_time] == trade[:open_time] && 
            p[:type] == trade[:type]
          }
          
          # 決済後のポジション数を記録
          trade[:exit_positions_count] = active_positions[symbol].size
          
          # 決済情報の追加
          trade[:exit_balance] = running_balance
          trade[:exit_equity] = running_balance
          trade[:exit_margin] = calculate_total_margin(active_positions)
          trade[:exit_free_margin] = running_balance - trade[:exit_margin]
          
          # トレード理由が設定されていない場合のデフォルト値
          if !trade[:reason] || trade[:reason].empty?
            trade[:reason] = get_default_entry_reason(trade)
          end
          
          if !trade[:exit_reason] || trade[:exit_reason].empty?
            trade[:exit_reason] = get_default_exit_reason(trade)
          end
          
          # エントリー理由に現在のポジション数を追加
          if trade[:entry_positions_count] > 0
            trade[:reason] = "#{trade[:reason]} (保有ポジション: #{trade[:entry_positions_count]})"
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
      
      # 保有ポジション全体の必要証拠金を計算
      def calculate_total_margin(active_positions)
        total_margin = 0
        
        active_positions.each do |symbol, positions|
          positions.each do |pos|
            # 各ポジションの証拠金を計算して合計
            pos_margin = calculate_margin(pos[:lot], pos[:open_price])
            total_margin += pos_margin
          end
        end
        
        total_margin
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
      

      # process_tick_data メソッドの修正
      def process_tick_data(tick_data)
        # テクニカル指標データの準備
        prepare_indicators(tick_data)

        # 各ティックを処理
        tick_data.each_with_index do |tick, index|
          # プログレス表示
          if index % 1000 == 0 && index > 0
            puts "ティック処理中: #{index}/#{tick_data.size}"
          end
          
          # アカウント情報更新
          update_account(tick)
          
          # コアロジックに処理を委譲（ここでMA計算も更新される）
          @core_logic.process_tick(tick, @account)
          
          # 【修正】MA値の記録を毎分実行
          current_minute = tick[:time].strftime('%Y-%m-%d %H:%M')
          @last_record_minute ||= ""
          
          # 毎分または最後のティックで記録
          if @last_record_minute != current_minute || index == tick_data.size - 1
            record_indicator_data_safely(tick, index)
            @last_record_minute = current_minute
          end
        end
      end

      def record_indicator_data_safely(tick, index)
        return unless @core_logic && @core_logic.indicator_calculator
        
        begin
          # MA計算に必要な最小データ数をチェック
          candles = @core_logic.instance_variable_get(:@candles)
          return unless candles && candles.size >= 14
          
          # MA インジケーターを取得
          fast_ma_indicator = @core_logic.indicator_calculator.indicators[:fast_ma]
          slow_ma_indicator = @core_logic.indicator_calculator.indicators[:slow_ma]
          
          return unless fast_ma_indicator && slow_ma_indicator
          
          # MA値を取得
          fast_ma = fast_ma_indicator.current_value
          slow_ma = slow_ma_indicator.current_value
          
          # 値の検証
          current_price = tick[:close].to_f
          
          # MA値の妥当性チェック（より厳格に）
          if fast_ma && fast_ma.is_a?(Numeric) && fast_ma.finite?
            # 価格との差が異常に大きくないかチェック（10%以内）
            price_diff_percent = ((fast_ma - current_price).abs / current_price) * 100
            
            if price_diff_percent > 10.0
              puts "異常なFastMA値を検出: MA=#{fast_ma.round(5)}, 価格=#{current_price.round(5)}, 差=#{price_diff_percent.round(2)}%" if @debug_mode
              fast_ma = nil  # 異常値は記録しない
            end
          else
            fast_ma = nil
          end
          
          if slow_ma && slow_ma.is_a?(Numeric) && slow_ma.finite?
            # 価格との差が異常に大きくないかチェック（10%以内）
            price_diff_percent = ((slow_ma - current_price).abs / current_price) * 100
            
            if price_diff_percent > 10.0
              puts "異常なSlowMA値を検出: MA=#{slow_ma.round(5)}, 価格=#{current_price.round(5)}, 差=#{price_diff_percent.round(2)}%" if @debug_mode
              slow_ma = nil  # 異常値は記録しない
            end
          else
            slow_ma = nil
          end
          
          # 前回値との比較チェック（同じ値が連続しすぎないように）
          if @indicators_data[:ma_fast].any? && fast_ma
            last_fast_ma = @indicators_data[:ma_fast].last[:value]
            if (fast_ma - last_fast_ma).abs < 0.000001
              @consecutive_same_fast_ma ||= 0
              @consecutive_same_fast_ma += 1
              
              if @consecutive_same_fast_ma > 100 && @debug_mode
                puts "警告: FastMAが#{@consecutive_same_fast_ma}回連続で同じ値です (#{fast_ma.round(5)})"
                
                # 原因調査のため、最新のローソク足データを確認
                recent_candles = candles.last(10)
                puts "最新10本の終値: #{recent_candles.map { |c| c[:close].round(5) }}"
              end
            else
              @consecutive_same_fast_ma = 0
            end
          end
          
          if @indicators_data[:ma_slow].any? && slow_ma
            last_slow_ma = @indicators_data[:ma_slow].last[:value]
            if (slow_ma - last_slow_ma).abs < 0.000001
              @consecutive_same_slow_ma ||= 0
              @consecutive_same_slow_ma += 1
              
              if @consecutive_same_slow_ma > 100 && @debug_mode
                puts "警告: SlowMAが#{@consecutive_same_slow_ma}回連続で同じ値です (#{slow_ma.round(5)})"
              end
            else
              @consecutive_same_slow_ma = 0
            end
          end
          
          # 有効な値のみ記録
          if fast_ma && fast_ma.is_a?(Numeric) && fast_ma.finite?
            @indicators_data[:ma_fast] << {
              time: tick[:time],
              value: fast_ma.round(5)
            }
          end
          
          if slow_ma && slow_ma.is_a?(Numeric) && slow_ma.finite?
            @indicators_data[:ma_slow] << {
              time: tick[:time],
              value: slow_ma.round(5)
            }
          end
          
          # デバッグ情報（必要に応じて）
          if @debug_mode && (fast_ma || slow_ma)
            # 価格変化がある場合のみ出力
            if (@indicators_data[:ma_fast].size % 60 == 0) || 
              (@indicators_data[:ma_fast].size > 1 && 
                (@indicators_data[:ma_fast].last[:value] - @indicators_data[:ma_fast][-2][:value]).abs > 0.00001)
              
              puts "MA記録: #{tick[:time].strftime('%H:%M')} 価格=#{current_price.round(5)} FastMA=#{fast_ma&.round(5)} SlowMA=#{slow_ma&.round(5)}"
            end
          end
          
        rescue => e
          puts "MA記録エラー: #{e.message}" if @debug_mode
          puts e.backtrace.first(3) if @debug_mode
        end
      end

      def record_indicator_data(tick, index)
        # インジケーターが初期化されているか確認
        return unless @core_logic && @core_logic.respond_to?(:indicator_calculator) && @core_logic.indicator_calculator

        # 十分なデータがあるかチェック
        return unless @core_logic.indicator_calculator.indicators

        begin
          fast_ma_indicator = @core_logic.indicator_calculator.indicators[:fast_ma]
          slow_ma_indicator = @core_logic.indicator_calculator.indicators[:slow_ma]
          
          # データが十分にあるかチェック
          if fast_ma_indicator && fast_ma_indicator.data.size >= 5  # 5期間MA用
            fast_ma = fast_ma_indicator.current_value
          end
          
          if slow_ma_indicator && slow_ma_indicator.data.size >= 14  # 14期間MA用
            slow_ma = slow_ma_indicator.current_value
          end
          
          # モメンタム値を取得
          momentum_value = nil
          if @core_logic.indicator_calculator.indicators[:momentum]
            momentum_indicator = @core_logic.indicator_calculator.indicators[:momentum]
            if momentum_indicator.respond_to?(:current_value) && momentum_indicator.data.size >= 20
              momentum_value = momentum_indicator.current_value
            end
          end
          
          # データを記録（nilでない場合のみ）
          if fast_ma
            @indicators_data[:ma_fast] << {
              time: tick[:time],
              value: fast_ma
            }
          end
          
          if slow_ma
            @indicators_data[:ma_slow] << {
              time: tick[:time],
              value: slow_ma
            }
          end
          
          if momentum_value
            @indicators_data[:momentum] << {
              time: tick[:time],
              value: momentum_value
            }
          end
          
        rescue => e
          puts "インジケーターデータの記録中にエラーが発生しました: #{e.message}" if @debug_mode
          puts e.backtrace.first(3) if @debug_mode
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