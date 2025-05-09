module MT4Backtester
  module Strategies
    module Trevian
      class CoreLogic
        # 戦略パラメータ
        attr_reader :params, :indicator_calculator
        attr_accessor :logger
        
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
            initial_balance: @params[:Start_Sikin],
            margin: 0
          }

          # 注文管理状態
          @orders = []
          @orders_in_progress = []
          @total_profit = 0
          @max_drawdown = 0
          @positions = []

          @debug_mode = debug_mode
          @logger = nil

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
        
        def set_balance_update_callback(callback)
          @on_balance_update = callback
        end

        def update_balance(profit)
          old_balance = @account_info[:balance]
          @account_info[:balance] += profit
          
          # デバッグ出力
          puts "CoreLogic: 残高更新 #{old_balance} -> #{@account_info[:balance]}" if @debug_mode
          
          # アカウント情報への参照を保持している親クラスに通知
          @on_balance_update.call(@account_info[:balance]) if @on_balance_update
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

        # 証拠金計算用のヘルパーメソッド
        def calculate_margin(lot_size, price)
          # 1ロット = 100,000通貨単位、レバレッジ100倍の場合の簡易計算
          contract_size = 100000
          leverage = @params[:leverage] || 100
          
          (lot_size * contract_size * price) / leverage
        end

        # ポジションの利益計算
        def calculate_position_profit(position, tick)
          if position[:type] == :buy
            (tick[:close] - position[:open_price]) * @params[:SpredKeisuu]
          else
            (position[:open_price] - tick[:close]) * @params[:SpredKeisuu]
          end
        end

        def pips
          symbol = @params[:Symbol] || 'GBPUSD'
          
          # シンボルに基づいて小数点以下の桁数とPoint値を決定
          symbol_info = case symbol
            when /JPY$/ then { digits: 3, point: 0.01 }      # 円ペア
            when 'GBPUSD', 'EURUSD', 'EURGBP' then { digits: 5, point: 0.00001 }
            else { digits: 4, point: 0.0001 }  # その他のメジャー通貨ペア
          end
          
          digits = symbol_info[:digits]
          point = symbol_info[:point]
          
          # MT4のPips関数を正確に模倣
          if digits == 3 || digits == 5
            # GBPUSDの場合: 0.00001 * 10 = 0.0001 を返す
            return (point * 10)
          elsif digits == 4 || digits == 2
            return point
          else
            return 0.1
          end
        end

        # 時間制御機能の実装
        def check_time_control(tick)
          time = tick[:time]
          # 曜日と時間を取得（Rubyの1=月曜を0=日曜にマッピングしてMT4と合わせる）
          day_of_week = time.wday  # 0=日曜, 1=月曜, ..., 6=土曜
          hour = time.hour
          
          # 状態を保持する変数
          @close_flag ||= 0
          
          # EA_Stop処理
          if @params[:EA_Stop] == 1
            @close_flag = 1 if @close_flag == 0
            return @close_flag
          elsif @params[:EA_Stop] == 2
            @close_flag = 0 if @close_flag == 1
            @params[:EA_Stop] = 0
            return @close_flag
          end
          
          # ポジション有無による条件分岐（MT4と同じ構造）
          if !@positions.empty? # OrderPosition > 0 と同等
            # 金曜日の20時以降または土曜日は手仕舞い
            if @close_flag == 0
              if day_of_week == 5 && hour >= 20
                @close_flag = 1
              elsif day_of_week == 6
                @close_flag = 1
              end
            end
          else
            # ポジションがない状態
            if day_of_week == 1 # 月曜日
              if hour >= 10
                @close_flag = 0
              elsif @close_flag == 0
                @close_flag = 1
              end
            elsif day_of_week > 1 && day_of_week < 5 # 火〜木曜
              @close_flag = 0 if @close_flag == 1
            end
          end
          
          return @close_flag
        end

        # ティックデータに対して戦略を適用
        def process_tick(tick, account_info)
          # アカウント情報の更新
          @account_info = account_info
          update_account_info(account_info)

        # EA_Stopチェック（手動停止）
        if @params[:EA_Stop] == 1
          @close_flag = 1
        elsif @params[:EA_Stop] == 2
          @close_flag = 0
          @params[:EA_Stop] = 0
        end
        
        # close_flagが立っている場合にポジションを閉じる
        if @close_flag == 1 && !@positions.empty?
          all_delete(tick)
          return
        end

          # トレーリングストップが有効な場合は、他の処理より優先して実行
          if @state[:trailing_stop_flag] == 1
            manage_trailing_stop(tick)
            return if @positions.empty?  # ポジションがすべて閉じられた場合は終了
          end

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
              all_delete(tick)
            end
          else
            # エントリーポイント判定
            entry_signal = check_entry_conditions(tick)
            # 新規エントリー
            if @positions.empty? && entry_signal != :none
              open_position(tick, entry_signal)
            end
            # 追加ポジション判定
            check_additional_positions(tick)
          end

          # トレーリングストップ管理
          manage_trailing_stop(tick) if @state[:trailing_stop_flag] == 1
          
          # ロスカット判定
          check_loss_cut(tick)
          # 指標データの準備（ログ出力用）
          prepare_indicators(tick) if @indicator_calculator.nil?
          
          # ログ出力（ロガーがセットされている場合）- 全ての処理が終わった後に実行
          if @logger
            # インジケーターの値を取得
            indicators = {}
            if @indicator_calculator
              indicators[:fast_ma] = @indicator_calculator.value(:fast_ma)
              indicators[:slow_ma] = @indicator_calculator.value(:slow_ma)
            end
            
            # 最新の状態情報
            state = @state.merge(close_flag: @close_flag || 0)
            
            # ログ出力 - 最新のアカウント情報を使用
            @logger.log(tick, indicators, state, @account_info)
          end

          if @debug_mode
           puts "====== #{tick[:time]} の状態 ======"
            puts "価格: #{tick[:close]}, MA5: #{@indicator_calculator.value(:fast_ma)}, MA14: #{@indicator_calculator.value(:slow_ma)}"
            puts "シグナル: #{entry_signal}, close_flag: #{@close_flag}, trailing_stop_flag: #{@state[:trailing_stop_flag]}"
            puts "ポジション数: #{@positions.size}, 口座残高: #{@account_info[:balance]}"
            
            if @positions.size > 0
              puts "ポジション詳細:"
              @positions.each_with_index do |pos, idx|
                puts "  #{idx+1}: #{pos[:type]} @ #{pos[:open_price]} (lot: #{pos[:lot_size]})"
              end
            end
            puts "============================="
          end
          #puts "#{params.inspect}"
        end
        
        # アカウント情報の更新
        def update_account_info(account_info)
          # 資金に応じた調整
          @params[:fukuri] = (account_info[:balance] / @params[:Start_Sikin]).floor
          @params[:fukuri] = 1 if @params[:fukuri] < 1
        end
        
        # エントリー条件の確認
        def check_entry_conditions(tick)

  # トレンド判定前のデバッグ出力
  puts "===== 初期パラメータ ====="
  puts "日時: #{tick[:time]}"
  puts "Gap: #{@params[:Gap]}, Takeprofit: #{@params[:Takeprofit]}, SpredKeisuu: #{@params[:SpredKeisuu]}"
  puts "next_order_keisu: #{@params[:next_order_keisu]}"
  puts "fukuri: #{@params[:fukuri]}, AccountBalance: #{@account_info[:balance]}"

          # MAやトレンド判定のためのデータを準備
          prepare_indicators(tick)

  # 移動平均値の取得
  fast_ma1 = @indicator_calculator.value(:fast_ma)
  fast_ma2 = @indicator_calculator.previous_value(:fast_ma, 1)
  slow_ma1 = @indicator_calculator.value(:slow_ma)
  slow_ma2 = @indicator_calculator.previous_value(:slow_ma, 1)
  
  # デバッグ出力 - 移動平均値
  puts "===== 移動平均値 ====="
  puts "FastMA1: #{fast_ma1}, FastMA2: #{fast_ma2}"
  puts "SlowMA1: #{slow_ma1}, SlowMA2: #{slow_ma2}"
  puts "FastMA1 > SlowMA1: #{fast_ma1} > #{slow_ma1}"
  puts "FastMA2 > SlowMA2: #{fast_ma2} > #{slow_ma2}"

          # トレンド判定
          trend = determine_trend

  # トレンド判定結果
  puts "トレンド判定: #{trend == :buy ? '買い (BUY)' : '売り (SELL)'}"

          return trend
        end
        
        # 指標データの準備
        def prepare_indicators(tick)
          # この部分を実装する必要があります
          if @indicator_calculator.nil?
            @indicator_calculator = MT4Backtester::Indicators::IndicatorCalculator.new
            
            # Trevianで使用される移動平均を追加(旧コード)
            #@indicator_calculator.add_ma(:fast_ma, 5)  # 短期移動平均（5期間）
            #@indicator_calculator.add_ma(:slow_ma, 14) # 長期移動平均（14期間）
            # 新しいMT4互換クラスを使用：
            # MT4互換のMAクラスのインスタンスを作成
            fast_ma = MT4Backtester::Indicators::MT4CompatibleMA.new(5, :sma, :close)
            slow_ma = MT4Backtester::Indicators::MT4CompatibleMA.new(14, :sma, :close)
            
            # インジケーターとして追加
            @indicator_calculator.add_indicator(:fast_ma, fast_ma)
            @indicator_calculator.add_indicator(:slow_ma, slow_ma)

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

  # デバッグ出力
  if @debug_mode
    puts "日時: #{@candles.last[:time]}"
    #puts "FastMA: #{@indicator_calculator.value(:fast_ma)}"
    #puts "SlowMA: #{@indicator_calculator.value(:slow_ma)}"
    fast_ma = @indicator_calculator.value(:fast_ma)
    slow_ma = @indicator_calculator.value(:slow_ma)
    
    puts "=== #{@candles.last[:time]} MA判定 ==="
    puts "FastMA(5): #{fast_ma}"
    puts "SlowMA(14): #{slow_ma}"
    puts "シグナル: #{ma_signal}"
    puts "========================="
  end

  # デバッグ情報の追加 - ここから
  if @candles.last && @debug_mode
    current_time = @candles.last[:time]
    if current_time.month == 1 && current_time.day >= 10 && current_time.day <= 16
      puts "  Signal: #{ma_signal}"
      
      # もし各ポジションの状態も確認したい場合は以下も追加
      if @positions && !@positions.empty?
        puts "  現在のポジション数: #{@positions.size}"
        puts "  次の注文タイプ: #{@state[:next_order] == 1 ? '買い' : '売り'}"
      end
      puts "-------------------------------"
    end
  end
  # デバッグ情報の追加 - ここまで

          return ma_signal
        end
        
        # ポジションのオープン
        def open_position(tick, signal)
          lot_size = calculate_lot_size
          # エントリー理由を追加
          entry_reason = get_entry_reason(signal)
          
          # ポジションを作成
          position = {
            ticket: generate_ticket_id,
            type: signal,
            open_time: tick[:time],
            open_price: signal == :buy ? tick[:close] : tick[:close],
            lot_size: lot_size,
            stop_loss: nil,
            take_profit: nil,
            reason: entry_reason,
            # 追加情報
            magic_number: @params[:MAGIC] || 8888,
            symbol: @params[:Symbol] || 'GBPUSD',
            # ポジション管理のための情報
            entry_positions_count: @positions.size
          }
          
          @positions << position
          
          # トレード履歴に追加
          trade_record = position.dup
          # 決済情報は未定義
          trade_record[:close_time] = nil
          trade_record[:close_price] = nil
          trade_record[:profit] = nil
          trade_record[:exit_reason] = nil
          
          # トレード記録に追加
          @orders_in_progress << trade_record
          
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
          
          return position
        end
        
        # 最適ロット計算（Trevianのロジックを再現）
        def calculate_optimal_lot(gap, profit, max_lot, positions)
  # デバッグ出力
  if @debug_mode
    puts "===== 極利計算開始 ====="
    puts "Gap: #{gap}, Takeprofit: #{profit}, MaxLotX: #{max_lot}"
    puts "LosCutPosition: #{positions}, LosCutProfit: #{@params[:LosCutProfit]}"
    puts "LosCutPlus: #{@params[:LosCutPlus]}, fukuri: #{@params[:fukuri]}"
    puts "MinusLot: #{@params[:MinusLot]}, アカウント残高: #{@account_info[:balance]}"  
  end
          # Trevianのロットサイズ計算（極利計算）
          start_lot = 0.01
          lot_coefficient = ((gap + profit) / profit) * @params[:keisu_x]
          next_order_keisu = lot_coefficient  # MT4の "次の注文係数" 変数を再現
          puts "次の注文係数: #{next_order_keisu}"

          lot_array = Array.new(positions, 0.0)
          total_lots = 0.0
          syokokin_lot = 0.0
          best_start_lot = start_lot
          
          # ロスカット設定に基づく調整
          #loss_cut_profit = @params[:LosCutProfit] 
          #loss_cut_plus = @params[:LosCutPlus]
  
          sikin = @account_info[:balance] +  @params[:LosCutProfit] + (@params[:LosCutPlus] * (@params[:fukuri] - 1))

          yojyou_syokokin = 0.0
          hituyou_syokokin = 0.0
          
          # マージン要件の計算 - 通貨ペアに応じた調整
          symbol = @params[:Symbol] || 'GBPUSD'
          margin_required_per_lot = case symbol
                                    when 'USDJPY', 'GBPJPY', 'EURJPY'
                                      1000.0 # 円通貨ペア
                                    when 'GBPUSD', 'EURUSD', 'EURAUD'
                                      #4000.0 # その他メジャー通貨ペア
                                      5000
                                    else
                                      100000.0 / 25.0 # デフォルト：MT4と同様の計算
                                    end

                                    puts "証拠金要件/ロット: ¥#{margin_required_per_lot}"
                                    puts "ロット係数: #{lot_coefficient}"
                                    puts "シキン（資金＋ロスカット): ¥#{sikin}"

  # MT4と同じロット探索アルゴリズム
  test_iterations = 0

# MT4と同じループ（0.01刻みでシミュレーション）
(1...(max_lot * 100).to_i + 1).each do |i|
  test_start_lot = i * 0.01
  test_iterations += 1
  
  # 初期化
  total_lots = 0.0
  syokokin_lot = 0.0
  
  # 初期ポジションのロット設定
  lot_array[0] = test_start_lot
  
  # MT4の実装と完全に一致させる
  max_lot_flag = 0
  
  # ポジションごとのロット計算
  (1...positions).each do |j|
    # MT4と同じロット計算式
    next_lot = (lot_array[j-1] * lot_coefficient + @params[:keisu_pulus_pips])
    # 小数点以下2桁に切り上げ（MT4と同じ）
    lot_array[j] = (next_lot * 100).ceil / 100.0
    
    # MT4と同じポジション分類ロジック
    if positions == 2 || positions == 4 || positions == 6 || positions == 8
      if j % 2 == 1  # ポジション2, 4, 6のロット
        total_lots += lot_array[j]
      end
      if j % 2 == 0  # ポジション1, 3, 5のロット
        syokokin_lot += lot_array[j]
      end
    elsif positions == 3 || positions == 5 || positions == 7
      if j % 2 == 1  # ポジション1, 3, 5のロット
        syokokin_lot += lot_array[j]
      end
      if j % 2 == 0  # ポジション2, 4のロット
        total_lots += lot_array[j]
      end
    end
    
    # 最大ロットチェック
    if total_lots >= max_lot || syokokin_lot >= max_lot
      max_lot_flag = 1
      break
    end
  end

    # デバッグ出力（テスト初期と0.1刻みで出力）
    if test_start_lot <= 0.05 || (test_start_lot % 0.1 == 0 && test_start_lot <= 0.5)
      lots_str = lot_array.map { |l| sprintf("%.2f", l) }.join(', ')
      puts "テスト[#{test_iterations}] lot:#{test_start_lot} - ロット配列:[#{lots_str}]"
      puts "  totalLots:#{total_lots.round(2)}, syokokinLot:#{syokokin_lot.round(2)}"
    end

  # MT4と同じ証拠金計算
  yojyou_syokokin = sikin - (syokokin_lot * margin_required_per_lot)
  hituyou_syokokin = total_lots * margin_required_per_lot

      # デバッグ出力（テスト初期と0.1刻みで出力）
      if test_start_lot <= 0.05 || (test_start_lot % 0.1 == 0 && test_start_lot <= 0.5)
        puts "  余剰証拠金: ¥#{yojyou_syokokin.round(2)}, 必要証拠金: ¥#{hituyou_syokokin.round(2)}"
        puts "  条件: #{yojyou_syokokin.round(2)} >= #{hituyou_syokokin.round(2)} ?: #{yojyou_syokokin >= hituyou_syokokin}"
      end
      
      # MT4と同じ判定ロジック
      if max_lot_flag == 1
        if test_start_lot <= 0.05 || (test_start_lot % 0.1 == 0 && test_start_lot <= 0.5)
          puts "  結果: 最大ロット超過のため中断"
        end
        break
      elsif yojyou_syokokin >= hituyou_syokokin
        best_start_lot = test_start_lot
        if test_start_lot <= 0.05 || (test_start_lot % 0.1 == 0 && test_start_lot <= 0.5)
          puts "  結果: このロットは可能 (best更新: #{best_start_lot})"
        end
      else
        if test_start_lot <= 0.05 || (test_start_lot % 0.1 == 0 && test_start_lot <= 0.5)
          puts "  結果: 証拠金不足のため中断"
        end
        break
      end
    end
    
    puts "テスト回数: #{test_iterations}"
    puts "計算された初期ロット: #{best_start_lot}"
    
    # 0.05を超える場合の調整（MT4パラメータに合わせる）
    adjusted_lot = best_start_lot
    if best_start_lot > 0.05
      adjusted_lot = best_start_lot - @params[:MinusLot]
      puts "調整後の初期ロット: #{adjusted_lot}"
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
            #puts "次のロット計算(初回): #{@positions.first[:lot_size]} * #{@params[:next_order_keisu]} + #{@params[:keisu_pulus_pips]} = #{next_lot}" if @debug_mode
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
            profit_zz_total = (@positions.size - @params[:position_x]) * @params[:Profit_down_Percent]
            
            # 次のロットサイズ調整係数も計算
            @lot_adjust_rate = 1.0 + (@params[:Profit_down_Percent] / 100.0)
            @lot_keisu_plus = @params[:keisu_pulus_pips] * @positions.size
            
            case @state[:next_order]
            when 1  # 次は買い
              rate_gap = @state[:buy_rate] - @state[:sell_rate]
              @state[:buy_rate] = @state[:sell_rate] + (rate_gap * gap_adjust_rate)
            when 2  # 次は売り
              rate_gap = @state[:buy_rate] - @state[:sell_rate]
              @state[:sell_rate] = @state[:buy_rate] - (rate_gap * gap_adjust_rate)
            end
            
            # Profit_down_Percentを反映したprofitの計算も行う
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
          #最も利益の大きいポジション
          #@positions.max_by { |pos| calculate_position_profit(pos, tick) }
          # 最大ロットのポジションを探す（MT4との一致を図る）
          @positions.max_by { |pos| pos[:lot_size] }
        end
        
        # ポジションのクローズ
        def close_position(position, tick, profit = nil)
          profit ||= calculate_position_profit(position, tick)
          old_balance = @account_info[:balance]  # 更新前の残高を記録
          update_balance(profit)

          # 決済理由を追加
          exit_reason = get_exit_reason(position, tick)
          
          trade = position.merge(
            close_time: tick[:time],
            close_price: tick[:close],
            profit: profit,
            position_count: @positions.size,  # ポジション数を追加
            exit_reason: exit_reason  # 決済理由を追加
          )

          @orders << trade
          @total_profit += profit
          # アカウント情報の残高を更新
          @account_info[:balance] += profit

  if @debug_mode
  # 残高更新のデバッグ出力
    puts "===== ポジション決済 ====="
    puts "時間: #{tick[:time]}"
    puts "ポジションタイプ: #{position[:type]}"
    puts "利益: #{profit}"
    puts "残高更新: #{old_balance} -> #{@account_info[:balance]}"
    puts "=========================="
  end
          # 最大ドローダウン更新
          update_max_drawdown
        end
        
        # トレーリングストップ管理
        def manage_trailing_stop(tick)
          # MT4と同じ順序で処理
          if @state[:trailing_stop_flag] == 1 && @positions.empty?
            @state[:trailing_stop_flag] = 0
            all_delete(tick)
            return
          end
          
          return unless @state[:trailing_stop_flag] == 1
          return if @positions.empty?
        
          position = @positions.first
          price = tick[:close]   # これは現在価格を使用
          pip_value = pips       # MT4のPips()と同等の実装を確認
        
          if position[:type] == :buy
            # 買いポジションのトレーリングストップ - OrderClosePrice()の代わりに現在価格を使用
            if position[:stop_loss].nil? || position[:stop_loss] < position[:open_price]
              profit = (price - position[:open_price]) / pip_value
              
              if profit > @params[:trailLength]
                position[:stop_loss] = position[:open_price]
                puts "Buy: 初期ストップロス設定 #{position[:stop_loss]}" if @debug_mode
              end
            else
              profit = (price - position[:stop_loss]) / pip_value
              
              if profit > @params[:trailLength] * 2
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
              all_delete(tick)
              puts "Buy: ストップロスヒット" if @debug_mode
            end
          elsif position[:type] == :sell
            # 売りポジションのトレーリングストップ
            if position[:stop_loss].nil? || position[:stop_loss] > position[:open_price]
              profit = (position[:open_price] - price) / pip_value
              
              if profit > @params[:trailLength]
                position[:stop_loss] = position[:open_price]
                puts "Sell: 初期ストップロス設定 #{position[:stop_loss]}" if @debug_mode
              end
            else
              profit = (position[:stop_loss] - price) / pip_value
              
              if profit > @params[:trailLength] * 2
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
              all_delete(tick)
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
            
            # すべてのポジションの損益を計算 - MT4と同様にスプレッドを考慮しない単純計算に
            #@positions.each do |pos|
            #  # シンプルな損益計算（MT4の TotalProfit に近づける）
            #  profit = calculate_position_profit(pos, tick)
            #  total_profit += profit
            #end

            # すべてのポジションの損益を計算（MT4と同様のシンプルな計算）
            @positions.each do |pos|
              if pos[:type] == :buy
                profit = (tick[:close] - pos[:open_price]) * pos[:lot_size] * 100000
              else
                profit = (pos[:open_price] - tick[:close]) * pos[:lot_size] * 100000
              end
              total_profit += profit
            end

            # 福利計算による損失閾値の調整
            loss_cut_profit = @params[:LosCutProfit] + (@params[:LosCutPlus] * (@params[:fukuri] - 1))
            
            if total_profit < loss_cut_profit
              # ロスカットフラグを設定（MT4互換）
              @loss_cut_flag = 1
              # すべてのポジションをクローズ
              all_delete(tick)
            end
          end
        end
        
        # ロット計算時にロスカットフラグをリセット
        def calculate_lot_size
          # ロスカットフラグのリセット
          @loss_cut_flag = 0
          
          # 極利計算によるロットサイズ
          lot = calculate_optimal_lot(
            @params[:Gap],
            @params[:Takeprofit],
            @params[:MaxLotX],
            @params[:LosCutPosition]
          )
            
  # MT4と同じ条件分岐
  if lot < 0.01
    lot = 0.01
  elsif lot > 0.05
    lot -= @params[:MinusLot]
  end
  
  puts "最終ロットサイズ: #{lot}"
          
          lot
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
          # 状態の完全リセット（MT4の実装に合わせる）
          @state[:orders] = 0
          @state[:buy_orders] = 0
          @state[:sell_orders] = 0
          @state[:limit_orders] = 0
          @state[:limit_buy_orders] = 0
          @state[:limit_sell_orders] = 0
          @state[:total_orders] = 0

          @state[:order_jyotai] = 0
          @state[:first_order] = 0
          @state[:next_order] = 0
          @state[:first_rate] = 0
          @state[:order_rate] = 0
          @state[:first_lots] = 0

          @state[:buy_rate] = 0
          @state[:sell_rate] = 0

          @state[:all_lots] = 0
          @state[:all_position] = 0

          @state[:trailing_stop_flag] = 0
          @state[:last_ticket] = 0
          @state[:last_lots] = 0
          
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

        # 現在のポジション情報を取得するメソッド
        def get_positions
          # @positionsだけでなく、ポジションの詳細情報も返す
          positions_with_details = @positions.map do |pos|
            # 既存の情報を取得
            {
              ticket: pos[:ticket],
              type: pos[:type],
              lot_size: pos[:lot_size],
              open_time: pos[:open_time],
              open_price: pos[:open_price],
              stop_loss: pos[:stop_loss],
              take_profit: pos[:take_profit],
              
              # 追加情報
              symbol: @params[:Symbol] || 'GBPUSD',  # シンボル
              magic_number: @params[:MAGIC] || 8888,          # マジックナンバー
              comment: pos[:type] == :buy ? "LONG" : "SHORT"  # コメント
            }
          end
          
          # ポジション数のログ出力（デバッグ用）
          if @debug_mode
            puts "現在のポジション数: #{@positions.size}"
            @positions.each_with_index do |pos, idx|
              puts "  ポジション #{idx+1}: #{pos[:type]} #{pos[:lot_size]}ロット @ #{pos[:open_price]}"
            end
          end
          
          positions_with_details
        end

        # 結果取得メソッドの拡張版
        def get_results
          total_profit = @orders.sum { |o| o[:profit] || 0 }
          winning_trades = @orders.count { |o| o[:profit] && o[:profit] > 0 }
          losing_trades = @orders.count { |o| o[:profit] && o[:profit] <= 0 }
          
          # 資金効率を計算
          profit_factor = 0
          
          # プロフィットファクターの計算
          if winning_trades > 0 && losing_trades > 0
            winning_sum = @orders.select { |o| o[:profit] && o[:profit] > 0 }.sum { |o| o[:profit] }
            losing_sum = @orders.select { |o| o[:profit] && o[:profit] <= 0 }.sum { |o| o[:profit] }.abs
            profit_factor = losing_sum > 0 ? (winning_sum / losing_sum).round(2) : winning_sum > 0 ? Float::INFINITY : 0
          end
          
          # 期待値の計算
          expected_payoff = @orders.size > 0 ? (total_profit / @orders.size).round(2) : 0
          
          {
            total_trades: @orders.size,
            winning_trades: winning_trades,
            losing_trades: losing_trades,
            total_profit: total_profit,
            max_drawdown: @max_drawdown,
            profit_factor: profit_factor,
            expected_payoff: expected_payoff,
            trades: @orders
          }
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
