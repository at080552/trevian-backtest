module MT4Backtester
  module Strategies
    module Trevian
      class CoreLogic
        # 戦略パラメータ
        attr_reader :params
        
        def initialize(params = {}, debug_mode = false)
          # デフォルトパラメータ
          @default_params = {
            Gap: 4000.0,
            Takeprofit: 60.0,
            Start_Lots: 0.95,
            Gap_down_Percent: 0,
            Profit_down_Percent: 0,
            strategy_test: 0,
            Start_Sikin: 300,
            MinusLot: 0.99,
            MaxLotX: 100,
            lot_seigen: 100,
            lot_pos_seigen: 30,
            fukuri: 1,
            limit_baisu: 10,
            keisu_x: 9.9,
            keisu_pulus_pips: 0.35,
            position_x: 1,
            SpredKeisuu: 10000,
            MAGIC: 8888,
            LosCutPosition: 15,
            LosCutProfit: -900,
            LosCutPlus: -40,
            trailLength: 99
          }

#自分で指定
require 'bigdecimal'
params[:Gap] = BigDecimal("103.2")
params[:Takeprofit] = BigDecimal("185.4")
params[:Start_Lots] = BigDecimal("0.01")
params[:Gap_down_Percent] = BigDecimal("0")
params[:Profit_down_Percent] = BigDecimal("0")
params[:keisu_x] = BigDecimal("1.3")
params[:keisu_pulus_pips] = BigDecimal("0.03")
params[:position_x] = 1
params[:LosCutPosition] = 5
params[:LosCutProfit] = -1500000
params[:LosCutPlus] = -600000
params[:trailLength] = BigDecimal("10")
params[:MaxLotX] = BigDecimal("18")
params[:MinusLot] = BigDecimal("0.02")
params[:Start_Sikin] = 4500000

          # パラメータのマージ（ユーザー指定のパラメータを優先）
          @params = @default_params.merge(params)
          
          # 計算パラメータ
          @params[:GapProfit] = @params[:Gap]
          @params[:next_order_keisu] = ((@params[:GapProfit] + @params[:Takeprofit]) / @params[:Takeprofit]) * @params[:keisu_x]
          @params[:profit_rate] = @params[:Takeprofit] / @params[:SpredKeisuu]
          
          # アカウント情報の初期化
          @account_info = {
            balance: @params[:Start_Sikin],
            equity: @params[:Start_Sikin],
            margin: 0
          }
          
          # 注文管理状態
          @orders = []
          @total_profit = 0
          @max_drawdown = 0
          @positions = []

          @debug_mode = debug_mode
          
          # 戦略実行状態
          reset_state
        end
        
        # 状態のリセット
        def reset_state
          @state = {
            orders: 0,
            buy_orders: 0,
            sell_orders: 0,
            limit_orders: 0,
            limit_buy_orders: 0,
            limit_sell_orders: 0,
            total_orders: 0,
            
            order_jyotai: 0,        # 0:first 1:rieki_serch
            first_order: 0,         # 1:Buy 2:Sell
            next_order: 0,          # 1:Buy 2:Sell
            first_rate: 0,
            order_rate: 0,
            first_lots: 0,
            
            buy_rate: 0,
            sell_rate: 0,
            
            all_lots: 0,
            all_position: 0,
            
            trailing_stop_flag: 0,
            last_ticket: 0,
            last_lots: 0
          }
        end
        
        # ティックデータに対して戦略を適用
        def process_tick(tick, account_info)
          # アカウント情報の更新
          @account_info = account_info
          update_account_info(account_info)
          
          # エントリーポイント判定
          entry_signal = check_entry_conditions(tick)
          
          # ポジション管理
          manage_positions(tick)
          
          # 新規エントリー
          if @positions.empty? && entry_signal != :none
            open_position(tick, entry_signal)
          end
          
          # 追加ポジション判定
          check_additional_positions(tick)
          
          # トレーリングストップ管理
          manage_trailing_stop(tick) if @state[:trailing_stop_flag] == 1
          
          # ロスカット判定
          check_loss_cut(tick)
        end
        
        # アカウント情報の更新
        def update_account_info(account_info)
          # 資金に応じた調整
          @params[:fukuri] = (account_info[:balance] / @params[:Start_Sikin]).floor
          @params[:fukuri] = 1 if @params[:fukuri] < 1
        end
        
        # エントリー条件の確認
        def check_entry_conditions(tick)
          # MAやトレンド判定のためのデータを準備
          prepare_indicators(tick)
          
          # トレンド判定
          trend = determine_trend
          
          return trend
        end
        
        # 指標データの準備
        def prepare_indicators(tick)
          # この部分を実装する必要があります
          # ローソク足データの生成（ティックデータから）
          # データがなければ@candlesを初期化
          if @candles.nil?
            @candles = []
            @indicator_calculator = MT4Backtester::Indicators::IndicatorCalculator.new
            
            # Trevianで使用される移動平均を追加
            @indicator_calculator.add_ma(:fast_ma, 5)  # 短期移動平均（5期間）
            @indicator_calculator.add_ma(:slow_ma, 14) # 長期移動平均（14期間）
          end
          
          # 新しいローソク足データの追加
          # 実際の実装ではティックデータからOHLCを生成する必要がある
          # 簡略化のためティックのcloseをそのまま使用
          new_candle = {
            time: tick[:time],
            open: tick[:open],
            high: tick[:high],
            low: tick[:low],
            close: tick[:close],
            volume: tick[:volume]
          }
          
          # 新しいローソク足を追加して指標再計算
          @candles << new_candle
          
          # 一定数以上になったら古いデータを削除（メモリ効率化）
          if @candles.length > 500
            @candles.shift
          end
          
          # 指標の計算
          @indicator_calculator.set_candles(@candles)
        end
        
        # トレンド判定
        def determine_trend
          # trend_hantei == 3 の場合（移動平均クロスオーバー）
          return :none if @candles.length < 15  # 十分なデータがない場合
          
          # 移動平均クロスオーバーによる判定
          ma_signal = @indicator_calculator.ma_crossover_check(:fast_ma, :slow_ma)
          
          # デバッグ出力（必要に応じて）
          #puts "MA Signal: #{ma_signal}, Fast MA: #{@indicator_calculator.value(:fast_ma)}, Slow MA: #{@indicator_calculator.value(:slow_ma)}"
          
          return ma_signal
        end
        
        # ポジションのオープン
        def open_position(tick, signal)
          lot_size = calculate_lot_size
          
          position = {
            ticket: generate_ticket_id,
            type: signal,
            open_time: tick[:time],
            open_price: signal == :buy ? tick[:close] : tick[:close],
            lot_size: lot_size,
            stop_loss: nil,
            take_profit: nil
          }
          
          @positions << position
          
          if signal == :buy
            @state[:buy_rate] = position[:open_price]
            @state[:sell_rate] = @state[:buy_rate] - (@params[:GapProfit] / @params[:SpredKeisuu])
            @state[:next_order] = 2  # 次は売り
          else
            @state[:sell_rate] = position[:open_price]
            @state[:buy_rate] = @state[:sell_rate] + (@params[:GapProfit] / @params[:SpredKeisuu])
            @state[:next_order] = 1  # 次は買い
          end
          
          # ポジション状態の更新
          update_position_state
        end
        
        # ロットサイズの計算
        def calculate_lot_size
          # 極利計算によるロットサイズ
          lot = calculate_optimal_lot(
            @params[:Gap],
            @params[:Takeprofit],
            @params[:MaxLotX],
            @params[:LosCutPosition]
          )
          
          lot = 0.01 if lot < 0.01
          lot -= @params[:MinusLot] if lot > 0.05
          
          lot
        end
        
        # 最適ロット計算（Trevianのロジックを再現）
# lib/mt4_backtester/strategies/trevian/core_logic.rb の calculate_optimal_lot メソッドを修正

      def calculate_optimal_lot(gap, profit, max_lot, positions)
        # Trevianのロットサイズ計算（極利計算）
        start_lot = 0.01
        lot_coefficient = ((gap + profit) / profit) * 1.3
        lot_array = Array.new(positions, 0.0)
        total_lots = 0.0
        syokokin_lot = 0.0
        best_start_lot = start_lot
        
        # ロスカット設定に基づく調整
        loss_cut_profit = @params[:LosCutProfit] + (@params[:LosCutPlus] * (@params[:fukuri] - 1))
        sikin = @account_info[:balance] + loss_cut_profit
        yojyou_syokokin = 0.0
        hituyou_syokokin = 0.0
        
        # マージン要件の計算（MT4ではMarginRequiredPerLotとして計算）
        margin_required_per_lot = 1000.0  # デフォルト値
        
        # 最適なスタートロットを探索
        max_test_lot = [max_lot, 100.0].min  # 上限を設ける
        
        for test_start_lot in (1..max_test_lot*100).map {|i| i / 100.0}
          total_lots = 0.0
          syokokin_lot = 0.0
          
          # 最初のポジションのロット設定
          lot_array[0] = test_start_lot
          
          # 各ポジションのロット計算
          max_lot_flag = 0
          
          for i in 1...positions
            # 次のロットサイズを計算（小数点2桁に丸める）
            lot_array[i] = ((lot_array[i-1] * lot_coefficient + 0.03) * 100).ceil / 100.0
            
            # 偶数・奇数位置に応じてロットを分類
            if positions == 2 || positions == 4 || positions == 6 || positions == 8
              if i % 2 == 1  # ポジション2, 4, 6のロット
                total_lots += lot_array[i]
              end
              if i % 2 == 0  # ポジション1, 3, 5のロット
                syokokin_lot += lot_array[i]
              end
            elsif positions == 3 || positions == 5 || positions == 7
              if i % 2 == 1  # ポジション1, 3, 5のロット
                syokokin_lot += lot_array[i]
              end
              if i % 2 == 0  # ポジション2, 4のロット
                total_lots += lot_array[i]
              end
            end
            
            # 最大ロットチェック
            if total_lots >= max_lot || syokokin_lot >= max_lot
              max_lot_flag = 1
              break
            end
          end
          
          # 証拠金計算
          yojyou_syokokin = sikin - (syokokin_lot * margin_required_per_lot)
          hituyou_syokokin = total_lots * margin_required_per_lot
          
          # 最適解の判定
          if max_lot_flag == 1
            break
          elsif yojyou_syokokin >= hituyou_syokokin
            best_start_lot = test_start_lot
          else
            break
          end
        end
        
        # デバッグ出力
        if @debug_mode
          puts "極利ロット計算結果: #{best_start_lot}"
          puts "資金: #{sikin}, 余剰証拠金: #{yojyou_syokokin}, 必要証拠金: #{hituyou_syokokin}"
        end
        
        return best_start_lot
      end
        
        # ポジション状態の更新
        def update_position_state
          @state[:orders] = 0
          @state[:buy_orders] = 0
          @state[:sell_orders] = 0
          @state[:all_lots] = 0
          @state[:all_position] = @positions.size
          
          @positions.each do |pos|
            @state[:orders] += 1
            if pos[:type] == :buy
              @state[:buy_orders] += 1
            else
              @state[:sell_orders] += 1
            end
            @state[:all_lots] += pos[:lot_size]
          end
        end
        
        # 追加ポジション判定
        def check_additional_positions(tick)
          return if @positions.empty?
          
          # 既存ポジションの逆方向に一定価格差でポジションを取る
          case @state[:next_order]
          when 1  # 次は買い
            if tick[:close] <= @state[:buy_rate]
              add_position(tick, :buy)
            end
          when 2  # 次は売り
            if tick[:close] >= @state[:sell_rate]
              add_position(tick, :sell)
            end
          end
        end
        
        # 追加ポジション
        def add_position(tick, type)
          # ポジション数制限のチェック
          return if @positions.size >= @params[:lot_pos_seigen]
          
          # ロット制限のチェック
          return if @state[:all_lots] >= @params[:lot_seigen]
          
          # ロットサイズの計算（Trevianのロジック再現）
          lot_size = calculate_next_lot_size
          
          position = {
            ticket: generate_ticket_id,
            type: type,
            open_time: tick[:time],
            open_price: type == :buy ? tick[:close] : tick[:close],
            lot_size: lot_size,
            stop_loss: nil,
            take_profit: nil
          }
          
          @positions << position
          
          # 次の注文準備
          if type == :buy
            @state[:next_order] = 2  # 次は売り
            # Gapの調整
            adjust_gap_for_next_position
          else
            @state[:next_order] = 1  # 次は買い
            # Gapの調整
            adjust_gap_for_next_position
          end
          
          # ポジション状態の更新
          update_position_state
        end
        
        # 次のロットサイズ計算
        def calculate_next_lot_size
          # Trevianの次のロットサイズ計算ロジック
          if @positions.size == 1
            # 最初の追加ポジション
            next_lot = @positions.first[:lot_size] * @params[:next_order_keisu] + @params[:keisu_pulus_pips]
            
            # デバッグ出力
            puts "次のロット計算(初回): #{@positions.first[:lot_size]} * #{@params[:next_order_keisu]} + #{@params[:keisu_pulus_pips]} = #{next_lot}" if @debug_mode
          else
            # 2回目以降の追加ポジション
            last_pos = @positions.last
            next_lot = last_pos[:lot_size] * @params[:next_order_keisu]
            
            # position_xより大きい場合はロットサイズを調整
            if @positions.size >= @params[:position_x]
              profit_zz_total = (@positions.size - @params[:position_x]) * @params[:Profit_down_Percent]
              lot_adjust_rate = 1.0 + (profit_zz_total / 100.0)
              keisu_plus = @params[:keisu_pulus_pips] * @positions.size
              
              # 調整後のロット
              next_lot = next_lot * lot_adjust_rate + keisu_plus
              
              # デバッグ出力
              puts "次のロット計算(調整): 基本 #{last_pos[:lot_size] * @params[:next_order_keisu]} * 調整率 #{lot_adjust_rate} + #{keisu_plus} = #{next_lot}" if @debug_mode
            else
              # デバッグ出力
              puts "次のロット計算: #{last_pos[:lot_size]} * #{@params[:next_order_keisu]} = #{next_lot}" if @debug_mode
            end
          end
          
          # ロットサイズを小数点第2位まで丸める
          next_lot = (next_lot * 100).ceil / 100.0
          
          return next_lot
        end
        
        # 次のポジション用にGapを調整
        def adjust_gap_for_next_position
          # position_xより大きい場合はGapを調整
          if @positions.size >= @params[:position_x]
            # ポジション数に応じたGap調整率の計算
            gap_adjust_rate = 1.0 - (@params[:Gap_down_Percent] / 100.0)
            
            case @state[:next_order]
            when 1  # 次は買い
              rate_gap = @state[:buy_rate] - @state[:sell_rate]
              @state[:buy_rate] = @state[:sell_rate] + (rate_gap * gap_adjust_rate)
              
              # デバッグ出力
              puts "Gap調整(買い): 元レート #{@state[:buy_rate] - (rate_gap * gap_adjust_rate)} → 新レート #{@state[:buy_rate]}" if @debug_mode
            when 2  # 次は売り
              rate_gap = @state[:buy_rate] - @state[:sell_rate]
              @state[:sell_rate] = @state[:buy_rate] - (rate_gap * gap_adjust_rate)
              
              # デバッグ出力
              puts "Gap調整(売り): 元レート #{@state[:sell_rate] + (rate_gap * gap_adjust_rate)} → 新レート #{@state[:sell_rate]}" if @debug_mode
            end
            
            # Profit_down_Percentを反映したprofitの計算も行う
            profit_zz_total = (@positions.size - @params[:position_x]) * @params[:Profit_down_Percent]
            @current_profit_target = @params[:Takeprofit] * (1 - (profit_zz_total / 100.0))
          end
        end
        
        # ポジション管理
        def manage_positions(tick)
          return if @positions.empty?
          
          # 利益確認
          check_profit(tick)
        end
        
        # 利益確認
        def check_profit(tick)
          # Trevianの利益確認ロジック実装
          profit_pips = @params[:Takeprofit]
          
          # ポジション数に応じた利益調整
          if @positions.size > @params[:position_x]
            profit_zz_total = (@positions.size - @params[:position_x]) * @params[:Profit_down_Percent]
            profit_pips = @params[:Takeprofit] * (1 - (profit_zz_total / 100.0))
          end
          
          # 最新のポジションで利益チェック
          if @positions.last
            current_profit = calculate_position_profit(@positions.last, tick)
            
            if current_profit >= profit_pips
              # トレーリングストップ開始
              start_trailing_stop(tick)
            end
          end
        end
        
        # ポジションの利益計算
        def calculate_position_profit(position, tick)
          if position[:type] == :buy
            (tick[:close] - position[:open_price]) * @params[:SpredKeisuu]
          else
            (position[:open_price] - tick[:close]) * @params[:SpredKeisuu]
          end
        end
        
        # トレーリングストップ開始
        def start_trailing_stop(tick)
          return if @positions.empty?
          
          # 最も利益の出ているポジションを残して他をクローズ
          last_position = find_most_profitable_position(tick)
          
          if last_position
            # 他のポジションをクローズ
            @positions.each do |pos|
              next if pos == last_position
              close_position(pos, tick)
            end
            
            # ポジションリストの更新
            @positions = [last_position]
            
            # トレーリングストップフラグをセット
            @state[:trailing_stop_flag] = 1
            @state[:last_ticket] = last_position[:ticket]
            @state[:last_lots] = last_position[:lot_size]
            
            # ポジション状態の更新
            update_position_state
          end
        end
        
        # 最も利益の出ているポジションを探す
        def find_most_profitable_position(tick)
          return nil if @positions.empty?
          
          @positions.max_by { |pos| calculate_position_profit(pos, tick) }
        end
        
        # ポジションのクローズ
        def close_position(position, tick, profit = nil)
          profit ||= calculate_position_profit(position, tick)
          
          trade = position.merge(
            close_time: tick[:time],
            close_price: tick[:close],
            profit: profit
          )
          
          @orders << trade
          @total_profit += profit
          
          # 最大ドローダウン更新
          update_max_drawdown
        end
        
        # トレーリングストップ管理
        def manage_trailing_stop(tick)
          return unless @state[:trailing_stop_flag] == 1
          return if @positions.empty?
          
          position = @positions.first
          
          if position[:type] == :buy
            if position[:stop_loss].nil? || position[:stop_loss] < position[:open_price]
              # 利益が一定以上あればストップを設定
              profit = (tick[:close] - position[:open_price]) / pips
              if profit > @params[:trailLength]
                position[:stop_loss] = position[:open_price]
              end
            else
              # ストップを徐々に引き上げる
              profit = (tick[:close] - position[:stop_loss]) / pips
              if profit > @params[:trailLength] * 2
                position[:stop_loss] += @params[:trailLength] * pips
              end
            end
            
            # ストップロスヒットの確認
            if position[:stop_loss] && tick[:close] <= position[:stop_loss]
              close_position(position, tick)
              @positions.clear
              @state[:trailing_stop_flag] = 0
            end
          elsif position[:type] == :sell
            if position[:stop_loss].nil? || position[:stop_loss] > position[:open_price]
              # 利益が一定以上あればストップを設定
              profit = (position[:open_price] - tick[:close]) / pips
              if profit > @params[:trailLength]
                position[:stop_loss] = position[:open_price]
              end
            else
              # ストップを徐々に引き下げる
              profit = (position[:stop_loss] - tick[:close]) / pips
              if profit > @params[:trailLength] * 2
                position[:stop_loss] -= @params[:trailLength] * pips
              end
            end
            
            # ストップロスヒットの確認
            if position[:stop_loss] && tick[:close] >= position[:stop_loss]
              close_position(position, tick)
              @positions.clear
              @state[:trailing_stop_flag] = 0
            end
          end
        end
        
        # ロスカット判定
        def check_loss_cut(tick)
          return if @positions.empty?
          
          # ポジション数がLosCutPosition以上の場合、利益をチェック
          if @positions.size >= @params[:LosCutPosition]
            total_profit = 0
            
            @positions.each do |pos|
              total_profit += calculate_position_profit(pos, tick)
            end
            
            loss_cut_profit = @params[:LosCutProfit] + (@params[:LosCutPlus] * (@params[:fukuri] - 1))
            
            if total_profit < loss_cut_profit
              # 全ポジションをクローズ
              @positions.each do |pos|
                close_position(pos, tick)
              end
              
              @positions.clear
              @state[:trailing_stop_flag] = 0
              
              # ポジション状態の更新
              update_position_state
            end
          end
        end
        
        # 最大ドローダウン更新
        def update_max_drawdown
          # 残高の履歴から最大ドローダウンを計算
          # 簡易実装
        end
        
        # チケットID生成
        def generate_ticket_id
          Time.now.to_i + rand(1000)
        end
        
        # pips値の取得
        def pips
          0.0001  # 4桁の通貨の場合
        end
        
        # 結果の取得
        def get_results
          {
            total_trades: @orders.size,
            winning_trades: @orders.count { |o| o[:profit] > 0 },
            losing_trades: @orders.count { |o| o[:profit] <= 0 },
            total_profit: @total_profit,
            max_drawdown: @max_drawdown,
            trades: @orders
          }
        end
      end
    end
  end
end
