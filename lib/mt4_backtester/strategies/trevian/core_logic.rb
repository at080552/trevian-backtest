module MT4Backtester
  module Strategies
    module Trevian
      class CoreLogic
        # 戦略パラメータ
        attr_reader :params, :indicator_calculator
        
        def initialize(params = {}, debug_mode = false)
          # 環境変数から設定を読み込む
          env_params = MT4Backtester::Config::ConfigLoader.load
          
          # パラメータのマージ（ユーザー指定のパラメータを優先）
          @params = env_params.merge(params)
          @indicator_calculator = nil
          @candles = []  # ここでローソク足データを保持する配列を初期化

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

          # 通貨ペアの設定
          set_spred_keisuu(params[:Symbol])

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

        # 通貨ペアに応じたSpredKeisuu設定
        def set_spred_keisuu(symbol = nil)
          symbol ||= @params[:Symbol] || 'GBPUSD'
          
          # 通貨ペアに応じて調整係数を設定
          case symbol
          when 'USDJPY', 'GBPJPY', 'EURJPY', 'AUDJPY', 'GOLD'
            @params[:SpredKeisuu] = 100
          when 'GBPUSD', 'EURUSD', 'EURAUD', 'AUDNZD', 'AUDCAD', 'EURGBP'
            @params[:SpredKeisuu] = 10000
          else
            # デフォルト値
            @params[:SpredKeisuu] = 10000
          end
          
          puts "通貨ペア: #{symbol}, SpredKeisuu: #{@params[:SpredKeisuu]}" if @debug_mode
          
          # profit_rateも更新
          @params[:profit_rate] = @params[:Takeprofit] / @params[:SpredKeisuu]
        end

        # スプレッドを考慮したポジション損益計算
        def calculate_position_profit_with_spread(position, tick)
          # スプレッド値を想定（実際のバックテストデータではスプレッド情報がないかもしれないので注意）
          spread = tick[:spread] || 2.0  # スプレッドがない場合は2.0pipsを想定
          
          if position[:type] == :buy
            # 買いポジションの損益計算
            profit = (tick[:close] - position[:open_price]) * @params[:SpredKeisuu]
            # スプレッドを考慮した実質損益（決済コスト考慮）
            real_profit = profit - (spread * position[:lot_size])
            return real_profit
          else
            # 売りポジションの損益計算
            profit = (position[:open_price] - tick[:close]) * @params[:SpredKeisuu]
            # スプレッドを考慮した実質損益（決済コスト考慮）
            real_profit = profit - (spread * position[:lot_size])
            return real_profit
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

        # Pips値の計算
        def pips
          symbol = @params[:Symbol] || 'GBPUSD'
          
          # シンボルに基づいて小数点以下の桁数を決定
          digits = case symbol
            when /JPY$/ then 3  # 円ペア
            when 'GBPUSD', 'EURUSD', 'EURGBP' then 5
            else 4
          end
          
          # MT4のPips関数を模倣
          if digits == 3 || digits == 5
            return (0.0001 * 10).round(digits - 1)
          elsif digits == 4 || digits == 2
            return 0.0001
          else
            return 0.1
          end
        end

        # 時間制御機能の実装
        def check_time_control(tick)
          time = tick[:time]
          # 曜日と時間を取得
          day_of_week = time.wday  # 0=日曜, 1=月曜, ..., 6=土曜
          hour = time.hour
          
          # 状態を保持する変数
          @close_flag ||= 0
          
          # 金曜日(5)の場合
          if day_of_week == 5 && hour >= 20
            @close_flag = 1 if @close_flag == 0
          end
          
          # 土曜日(6)の場合
          if day_of_week == 6
            @close_flag = 1
          end
          
          # 月曜日(1)の場合で保有ポジションがない場合
          if day_of_week == 1
            if hour >= 10
              @close_flag = 0
            elsif @close_flag == 0 && @positions.empty?
              @close_flag = 1
            end
          end
          
          # 火曜から木曜(2-4)の場合
          if day_of_week >= 2 && day_of_week <= 4
            @close_flag = 0 if @close_flag == 1
          end
          
          return @close_flag
        end

        # ティックデータに対して戦略を適用
        def process_tick(tick, account_info)
          # 日時表示
          #puts "処理日時: #{tick[:time]}"
          # エントリー条件チェック
          #entry_signal = check_entry_conditions(tick)
          #puts "エントリーシグナル: #{entry_signal}, ポジション数: #{@positions.size}"

          # アカウント情報の更新
          @account_info = account_info
          update_account_info(account_info)
          
          # 時間制御確認
          time_control = check_time_control(tick)
          
          # ポジション管理（常に実行）
          manage_positions(tick)
          
          # 時間制御がアクティブな場合は新規取引を行わない
          if time_control == 1
            # ポジションがある場合は決済を検討
            if !@positions.empty?
              # 金曜日や週末のポジション決済ロジックをここに実装
              # 実際のMT4版では金曜日の夜などに積極的な決済を行う
            end
            return
          end
          
          # 以下は既存コード
          # エントリーポイント判定
          entry_signal = check_entry_conditions(tick)
          
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
          if @indicator_calculator.nil?
            @indicator_calculator = MT4Backtester::Indicators::IndicatorCalculator.new
            
            # Trevianで使用される移動平均を追加
            @indicator_calculator.add_ma(:fast_ma, 5)  # 短期移動平均（5期間）
            @indicator_calculator.add_ma(:slow_ma, 14) # 長期移動平均（14期間）
            # モメンタム指標の追加
            @indicator_calculator.indicators ||= {}
            begin
              momentum = MT4Backtester::Indicators::Momentum.new(20)
              @indicator_calculator.indicators[:momentum] = momentum
              @indicator_calculator.calculate(momentum)
            rescue => e
              puts "モメンタム指標の追加に失敗しました: #{e.message}" if @debug_mode
            end
          end
          # ティックデータからローソク足を更新
          update_indicator_with_tick(tick)
        end

        # カンドルデータを更新する処理
        def update_indicator_with_tick(tick)
          return unless @indicator_calculator
          
          # 新しいカンドルを作成
          new_candle = {
            time: tick[:time],
            open: tick[:open],
            high: tick[:high],
            low: tick[:low],
            close: tick[:close],
            volume: tick[:volume]
          }
          
          # 新しいカンドルを追加するか、最後のカンドルを更新
          if @candles.empty? || (tick[:time] - @candles.last[:time]) >= 60  # 1分以上経過したら新しいカンドル
            @candles << new_candle
          else
            # 同じ時間枠内なら高値・安値・終値を更新
            last_candle = @candles.last
            last_candle[:high] = [last_candle[:high], tick[:high]].max
            last_candle[:low] = [last_candle[:low], tick[:low]].min
            last_candle[:close] = tick[:close]
            last_candle[:volume] += tick[:volume]
          end
          
          # 一定数以上になったら古いデータを削除（メモリ効率化）
          if @candles.length > 500
            @candles.shift
          end
          
          # インジケーターを更新
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
          # エントリー理由を追加
          entry_reason = get_entry_reason(signal)
          
          position = {
            ticket: generate_ticket_id,
            type: signal,
            open_time: tick[:time],
            open_price: signal == :buy ? tick[:close] : tick[:close],
            lot_size: lot_size,
            stop_loss: nil,
            take_profit: nil,
            reason: entry_reason  # 理由を追加
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

          # 決済理由を追加
          exit_reason = get_exit_reason(position, tick)
          
          trade = position.merge(
            close_time: tick[:time],
            close_price: tick[:close],
            profit: profit,
            exit_reason: exit_reason  # 決済理由を追加
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
          
          # トレーリングが有効でポジションがない場合は状態をリセット
          if @positions.empty?
            @state[:trailing_stop_flag] = 0
            return
          end
          
          position = @positions.first
          price = tick[:close]
          pip_value = pips  # Pips関数で計算した値
          
          if position[:type] == :buy
            # 買いポジションのトレーリングストップ
            if position[:stop_loss].nil? || position[:stop_loss] < position[:open_price]
              # 最初のストップロス設定（オープン価格に設定）
              profit = (price - position[:open_price]) / pip_value
              
              if profit > @params[:trailLength]
                # 利益が一定以上あればストップロスをオープン価格に設定
                position[:stop_loss] = position[:open_price]
                puts "Buy: 初期ストップロス設定 #{position[:stop_loss]}" if @debug_mode
              end
            else
              # ストップロスを徐々に引き上げる
              profit = (price - position[:stop_loss]) / pip_value
              
              if profit > @params[:trailLength] * 2
                # 新しいストップロスを計算
                new_stop_loss = position[:stop_loss] + (@params[:trailLength] * pip_value)
                position[:stop_loss] = new_stop_loss
                puts "Buy: ストップロス更新 #{position[:stop_loss]}" if @debug_mode
              end
            end
            
            # ストップロスヒットの確認
            if position[:stop_loss] && price <= position[:stop_loss]
              close_position(position, tick)
              @positions.clear
              @state[:trailing_stop_flag] = 0
              puts "Buy: ストップロスヒット" if @debug_mode
            end
            
          elsif position[:type] == :sell
            # 売りポジションのトレーリングストップ
            if position[:stop_loss].nil? || position[:stop_loss] > position[:open_price]
              # 最初のストップロス設定（オープン価格に設定）
              profit = (position[:open_price] - price) / pip_value
              
              if profit > @params[:trailLength]
                # 利益が一定以上あればストップロスをオープン価格に設定
                position[:stop_loss] = position[:open_price]
                puts "Sell: 初期ストップロス設定 #{position[:stop_loss]}" if @debug_mode
              end
            else
              # ストップロスを徐々に引き下げる
              profit = (position[:stop_loss] - price) / pip_value
              
              if profit > @params[:trailLength] * 2
                # 新しいストップロスを計算
                new_stop_loss = position[:stop_loss] - (@params[:trailLength] * pip_value)
                position[:stop_loss] = new_stop_loss
                puts "Sell: ストップロス更新 #{position[:stop_loss]}" if @debug_mode
              end
            end
            
            # ストップロスヒットの確認
            if position[:stop_loss] && price >= position[:stop_loss]
              close_position(position, tick)
              @positions.clear
              @state[:trailing_stop_flag] = 0
              puts "Sell: ストップロスヒット" if @debug_mode
            end
          end
        end

        def get_entry_reason(signal)
          if signal == :buy
            # 買いエントリーの理由
            if @indicator_calculator && @indicator_calculator.value(:fast_ma) && @indicator_calculator.value(:slow_ma)
              fast_ma = @indicator_calculator.value(:fast_ma)
              slow_ma = @indicator_calculator.value(:slow_ma)
              
              if fast_ma > slow_ma
                return "MA(5)がMA(14)を上回ったため"
              end
            end
            return "買いシグナル発生"
          else
            # 売りエントリーの理由
            if @indicator_calculator && @indicator_calculator.value(:fast_ma) && @indicator_calculator.value(:slow_ma)
              fast_ma = @indicator_calculator.value(:fast_ma)
              slow_ma = @indicator_calculator.value(:slow_ma)
              
              if fast_ma < slow_ma
                return "MA(5)がMA(14)を下回ったため"
              end
            end
            return "売りシグナル発生"
          end
        end
        
        def get_exit_reason(position, tick)
          # トレーリングストップによる決済
          if @state[:trailing_stop_flag] == 1
            return "トレーリングストップによる決済"
          end
          
          # 利益確定による決済
          profit = calculate_position_profit(position, tick)
          profit_pips = @params[:Takeprofit]
          
          if @positions.size > @params[:position_x]
            profit_zz_total = (@positions.size - @params[:position_x]) * @params[:Profit_down_Percent]
            profit_pips = @params[:Takeprofit] * (1 - (profit_zz_total / 100))
          end
          
          if profit >= profit_pips
            return "利益確定 (#{profit_pips.round(1)}pips)"
          end
          
          # ロスカットによる決済
          if profit < (@params[:LosCutProfit] + (@params[:LosCutPlus] * (@params[:fukuri] - 1)))
            return "ロスカット"
          end
          
          return "決済"
        end

        # ロスカット判定
        def check_loss_cut(tick)
          return if @positions.empty?
          
          # ポジション数がLosCutPosition以上の場合、利益をチェック
          if @positions.size >= @params[:LosCutPosition]
            total_profit = 0
            
            # すべてのポジションの損益を計算
            @positions.each do |pos|
              # スプレッドを考慮した損益計算
              profit = calculate_position_profit_with_spread(pos, tick)
              total_profit += profit
            end
            
            # 福利計算による損失閾値の調整
            loss_cut_profit = @params[:LosCutProfit] + (@params[:LosCutPlus] * (@params[:fukuri] - 1))
            
            puts "総損益: #{total_profit}, ロスカット閾値: #{loss_cut_profit}" if @debug_mode
            
            if total_profit < loss_cut_profit
              puts "ロスカット発動! 総ポジション数: #{@positions.size}, 総損益: #{total_profit}" if @debug_mode
              
              # すべてのポジションをクローズ
              all_delete(tick)
            end
          end
        end

        # すべてのポジションを削除
        def all_delete(tick)
          return if @positions.empty?
          
          # ロスカットフラグを設定
          @all_delete_flag = 1
          
          # すべてのポジションを閉じる
          @positions.each do |pos|
            close_position(pos, tick)
          end
          
          # ポジションをクリアし、状態をリセット
          @positions = []
          @state[:first_order] = 0
          @state[:next_order] = 0
          @state[:trailing_stop_flag] = 0
          @state[:first_rate] = 0
          @state[:order_rate] = 0
          
          # ロスカットフラグをリセット
          @all_delete_flag = 0
          
          # 状態更新
          update_position_state
          
          puts "すべてのポジションをクローズしました" if @debug_mode
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
