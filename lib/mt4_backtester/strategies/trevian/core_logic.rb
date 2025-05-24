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
          # MT4と同じハードコード値を強制的に設定
          @params[:lot_seigen] = 100.0      # 総ロット数制限
          @params[:lot_pos_seigen] = 30     # 最大ポジション数制限
          @indicator_calculator = nil
          @candles = []  # ここでローソク足データを保持する配列を初期化

          # JPY/USD変換を含むパラメータの初期化
          initialize_parameters
          
          # 計算パラメータ
          @params[:GapProfit] = @params[:Gap]
          @params[:next_order_keisu] = ((@params[:GapProfit] + @params[:Takeprofit]) / @params[:Takeprofit]) * @params[:keisu_x]
          @params[:profit_rate] = @params[:Takeprofit] / @params[:SpredKeisuu]

          # 初期の福利を計算
          @params[:fukuri] = (@params[:Start_Sikin].to_f / @params[:Start_Sikin].to_f).floor
          @params[:fukuri] = 1 if @params[:fukuri] < 1

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
          @balance_history = [@account_info[:balance]]
          @peak_balance = @account_info[:balance]
          @first_entry_done = false  # 最初のエントリー完了フラグを追加
          @buy_order_executed = false
          @sell_order_executed = false

          @debug_mode = debug_mode
          @logger = nil

          # 通貨ペアの設定
          set_spred_keisuu(params[:Symbol])

          # 戦略実行状態
          reset_state
        end

        def initialize_parameters
          # USDJPYレートの設定（初期値またはTick Dataから設定）
          @params[:USDJPY_rate] ||= 155.0  # デフォルト値
          
          # 円建てパラメータをドル建てに変換
          @params[:LosCutProfit_USD] = @params[:LosCutProfit] / @params[:USDJPY_rate]
          @params[:LosCutPlus_USD] = @params[:LosCutPlus] / @params[:USDJPY_rate]
          @params[:Start_Sikin_USD] = @params[:Start_Sikin] / @params[:USDJPY_rate]
          
          # デバッグ出力
          if @debug_mode
            puts "=== 通貨換算パラメータ ==="
            puts "USDJPYレート: #{@params[:USDJPY_rate]}"
            puts "ロスカット閾値: #{@params[:LosCutProfit]} JPY (#{@params[:LosCutProfit_USD]} USD)"
            puts "ロスカット追加: #{@params[:LosCutPlus]} JPY (#{@params[:LosCutPlus_USD]} USD)"
            puts "初期資金: #{@params[:Start_Sikin]} JPY (#{@params[:Start_Sikin_USD]} USD)"
          end
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

          # 残高履歴を保存
          @balance_history << @account_info[:balance]

          # ドローダウン計算
          update_max_drawdown

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

        # 証拠金計算用のヘルパーメソッド
        def calculate_margin(lot_size, price)
          # 基本パラメータの設定
          contract_size = 100000  # 1ロット = 10万通貨（GBP）
          margin_rate = 0.04      # 証拠金率4%（レバレッジ25倍）
          usdjpy_rate = @params[:USDJPY_rate] || 155.0
          
          # 直接計算（数量換算なし）
          usd_margin = lot_size * contract_size * price * margin_rate
          jpy_margin = usd_margin * usdjpy_rate
          
          # デバッグ情報
          if @debug_mode
            puts "ロット: #{lot_size}, レート: #{price}, USDJPY: #{usdjpy_rate}"
            puts "USD証拠金: #{usd_margin}, JPY証拠金: #{jpy_margin}"
          end
          
          return jpy_margin
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
  # **テスト用**: 時間制御を一時的に無効化
  puts "時間制御: 無効化中（テスト用）"
  return 0  # 常に取引可能状態を返す
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

def record_signal(tick, signal)
  # ログディレクトリの作成
  log_dir = 'logs'
  FileUtils.mkdir_p(log_dir) unless Dir.exist?(log_dir)
  
  # 日付フォーマット
  timestamp = tick[:time].strftime('%Y-%m-%d %H:%M:%S')
  
  # MA値の取得
  fast_ma = @indicator_calculator&.value(:fast_ma)
  slow_ma = @indicator_calculator&.value(:slow_ma)
  
  # CSV形式でログを記録
  File.open("#{log_dir}/signals.csv", 'a') do |f|
    f.puts "#{timestamp},#{tick[:close]},#{signal},#{fast_ma},#{slow_ma}"
  end
end

        # ティックデータに対して戦略を適用
def process_tick(tick, account_info)
  # 基本情報のログ
  puts "=== TICK処理: #{tick[:time].strftime('%H:%M')} ==="
  puts "価格: #{tick[:close]}, ポジション数: #{@positions.size}, ローソク足数: #{@candles.size}"
  
  # 同じ分内での重複処理を防ぐ
  current_minute = tick[:time].strftime('%H:%M')
  @last_processed_minute ||= ""
  
  if @last_processed_minute == current_minute && @positions.size > 0
    puts "同じ分内での重複処理をスキップ: #{current_minute}"
    return
  end
  
  @last_processed_minute = current_minute
  
  # アカウント情報の更新
  @account_info = account_info
  update_account_info(account_info)

  # 時間制御確認（テスト用に無効化）
  @close_flag = check_time_control(tick)
  puts "close_flag: #{@close_flag}"
  
  # ポジション管理（常に実行）
  manage_positions(tick)

  # エントリー判定の詳細ログ
  puts "=== エントリー判定 ==="
  puts "ポジション空?: #{@positions.empty?}"
  puts "first_entry_done?: #{@first_entry_done}"
  puts "close_flag: #{@close_flag}"

  # 新規エントリー判定
  if @positions.empty? && !@first_entry_done && @close_flag == 0
    puts "初回エントリー判定開始"
    
    # 指標データの準備
    prepare_indicators(tick)
    
    # エントリー条件チェック
    entry_signal = check_entry_conditions(tick)
    
    puts "エントリーシグナル: #{entry_signal}"
    
    # :none以外の場合のみエントリー
    if entry_signal != :none
      puts "=== エントリー実行開始 ==="
      position = open_first_position(tick, entry_signal)
      @first_entry_done = true
      
      if position
        puts "ポジション作成成功: #{position[:type]} #{position[:lot_size]}ロット @ #{position[:open_price]}"
      else
        puts "ポジション作成失敗"
      end
    else
      puts "エントリー条件不成立: #{entry_signal}"
    end
  else
    puts "エントリー条件不適合:"
    puts "  ポジション空: #{@positions.empty?}"
    puts "  first_entry_done: #{@first_entry_done}"
    puts "  close_flag: #{@close_flag}"
    
    # 既存ポジションがある場合の追加ポジション判定
    if !@positions.empty?
      puts "追加ポジション判定"
      check_additional_positions(tick)
    end
  end

  puts "=== TICK処理終了 ===\n"
end
        
        # アカウント情報の更新
        def update_account_info(account_info)
          # 資金に応じた調整（円建て）
          @params[:fukuri] = (account_info[:balance].to_f / @params[:Start_Sikin].to_f).floor
          @params[:fukuri] = 1 if @params[:fukuri] < 1
          
          # デバッグ出力
          if @debug_mode
            puts "福利更新: 残高=#{account_info[:balance]}円, 初期資金=#{@params[:Start_Sikin]}円, fukuri=#{@params[:fukuri]}"
          end
        end
        
        # エントリー条件の確認
        def check_entry_conditions(tick)
          # デバッグ出力
          if @debug_mode
            puts "===== 初期パラメータ ====="
            puts "日時: #{tick[:time]}"
            puts "Gap: #{@params[:Gap]}, Takeprofit: #{@params[:Takeprofit]}, SpredKeisuu: #{@params[:SpredKeisuu]}"
            puts "next_order_keisu: #{@params[:next_order_keisu]}"
            puts "fukuri: #{@params[:fukuri]}, AccountBalance: #{@account_info[:balance]}"
          end

          # MAやトレンド判定のためのデータを準備
          prepare_indicators(tick)

          # 移動平均値の取得
          fast_ma1 = @indicator_calculator.value(:fast_ma)
          fast_ma2 = @indicator_calculator.previous_value(:fast_ma, 1)
          slow_ma1 = @indicator_calculator.value(:slow_ma)
          slow_ma2 = @indicator_calculator.previous_value(:slow_ma, 1)
          
          # デバッグ出力 - 移動平均値（nil値を適切に表示）
          if @debug_mode
            puts "===== 移動平均値 ====="
            puts "FastMA1: #{fast_ma1 ? fast_ma1.round(6) : 'nil'}, FastMA2: #{fast_ma2 ? fast_ma2.round(6) : 'nil'}"
            puts "SlowMA1: #{slow_ma1 ? slow_ma1.round(6) : 'nil'}, SlowMA2: #{slow_ma2 ? slow_ma2.round(6) : 'nil'}"
            
            # nil値チェックを含む比較
            if fast_ma1 && slow_ma1
              puts "FastMA1 > SlowMA1: #{fast_ma1.round(6)} > #{slow_ma1.round(6)} = #{fast_ma1 > slow_ma1}"
            else
              puts "FastMA1 > SlowMA1: 比較不可（nil値あり）"
            end
            
            if fast_ma2 && slow_ma2
              puts "FastMA2 > SlowMA2: #{fast_ma2.round(6)} > #{slow_ma2.round(6)} = #{fast_ma2 > slow_ma2}"
            else
              puts "FastMA2 > SlowMA2: 比較不可（nil値あり）"
            end
          end

          # トレンド判定
          trend = determine_trend

          # トレンド判定結果
          if @debug_mode
            puts "トレンド判定: #{trend == :buy ? '買い (BUY)' : trend == :sell ? '売り (SELL)' : 'エントリーなし (NONE)'}"
          end

          return trend
        end
        
        # 指標データの準備
        def prepare_indicators(tick)
          # この部分を実装する必要があります
          if @indicator_calculator.nil?
            @indicator_calculator = MT4Backtester::Indicators::IndicatorCalculator.new(@debug_mode)
            
            # MT4互換のMAクラスのインスタンスを作成
            fast_ma = MT4Backtester::Indicators::MT4CompatibleMA.new(5, :sma, :close)
            slow_ma = MT4Backtester::Indicators::MT4CompatibleMA.new(14, :sma, :close)
            
            # デバッグモードを明示的に設定
            if @debug_mode
              fast_ma.instance_variable_set(:@debug_mode, true)
              slow_ma.instance_variable_set(:@debug_mode, true)
              puts "MovingAverageインジケーターをデバッグモードで初期化"
            end
            
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
            
            puts "インジケーター初期化完了: FastMA(5), SlowMA(14)" if @debug_mode
          end
          
          # ティックデータからローソク足を更新
          update_indicator_with_tick(tick)

          # デバッグ：移動平均の計算状況を確認
          if @debug_mode
            puts "=== 移動平均計算状況 ==="
            puts "ローソク足数: #{@candles.size}"
            
            fast_ma_val = @indicator_calculator.value(:fast_ma)
            slow_ma_val = @indicator_calculator.value(:slow_ma)
            
            puts "FastMA: #{fast_ma_val ? fast_ma_val.round(5) : 'nil'}"
            puts "SlowMA: #{slow_ma_val ? slow_ma_val.round(5) : 'nil'}"
            
            if @candles.size >= 14
              puts "14期間分のデータあり - SlowMAが計算されるはず"
              
              # 直接計算してみる
              if @candles.size >= 14
                recent_closes = @candles.last(14).map { |c| c[:close] }
                manual_slow_ma = recent_closes.sum / 14.0
                puts "手動計算SlowMA: #{manual_slow_ma.round(5)}"
                puts "実際のSlowMA: #{slow_ma_val ? slow_ma_val.round(5) : 'nil'}"
                
                # 5期間の手動計算も
                if @candles.size >= 5
                  recent_5_closes = @candles.last(5).map { |c| c[:close] }
                  manual_fast_ma = recent_5_closes.sum / 5.0
                  puts "手動計算FastMA: #{manual_fast_ma.round(5)}"
                  puts "実際のFastMA: #{fast_ma_val ? fast_ma_val.round(5) : 'nil'}"
                end
              end
            else
              puts "データ不足: SlowMAには#{14 - @candles.size}個不足"
            end
            
            # インジケーターの詳細情報
            fast_ma_indicator = @indicator_calculator.indicators[:fast_ma]
            slow_ma_indicator = @indicator_calculator.indicators[:slow_ma]
            
            if fast_ma_indicator.respond_to?(:debug_info)
              puts "FastMA詳細: #{fast_ma_indicator.debug_info}"
            end
            
            if slow_ma_indicator.respond_to?(:debug_info)
              puts "SlowMA詳細: #{slow_ma_indicator.debug_info}"
            end
          end
        end

def update_indicator_with_tick(tick)
  return unless @indicator_calculator
  
  # ティックデータの検証
  unless tick[:close] && tick[:time]
    puts "無効なティックデータをスキップ: #{tick.inspect}"
    return
  end
  
  # 分単位での時間正規化
  current_minute = Time.new(
    tick[:time].year, tick[:time].month, tick[:time].day,
    tick[:time].hour, tick[:time].min, 0
  )
  
  # 価格データの有効性チェック
  current_price = tick[:close].to_f
  if current_price <= 0
    puts "無効な価格データをスキップ: #{current_price}"
    return
  end
  
  candles_updated = false
  
  if @candles.empty?
    # 最初のローソク足を作成
    new_candle = {
      time: current_minute,
      open: current_price,
      high: current_price,
      low: current_price,
      close: current_price,
      volume: tick[:volume] || 1
    }
    @candles << new_candle
    candles_updated = true
    
    puts "初回ローソク足作成: 時間=#{current_minute.strftime('%H:%M')}, 価格=#{current_price}"
  else
    last_candle = @candles.last
    last_minute = last_candle[:time]
    
    # **重要な修正**: 時間比較を修正（秒単位の比較を除去）
    if current_minute > last_minute
      # 新しい分に入った - 新しいローソク足を作成
      new_candle = {
        time: current_minute,
        open: current_price,
        high: current_price,
        low: current_price,
        close: current_price,
        volume: tick[:volume] || 1
      }
      @candles << new_candle
      candles_updated = true
      
      puts "新規ローソク足作成: #{current_minute.strftime('%H:%M')} 価格=#{current_price} (ローソク足数: #{@candles.size})"
      puts "  前回: #{last_minute.strftime('%H:%M')}, 現在: #{current_minute.strftime('%H:%M')}"
    elsif current_minute == last_minute
      # 同じ分内 - 既存ローソク足を更新（価格が変化した場合のみ）
      old_close = last_candle[:close]
      
      # 価格変化がある場合のみ更新
      if (old_close - current_price).abs > 0.000001
        last_candle[:high] = [last_candle[:high], current_price].max
        last_candle[:low] = [last_candle[:low], current_price].min
        last_candle[:close] = current_price
        last_candle[:volume] = (last_candle[:volume] || 0) + (tick[:volume] || 1)
        candles_updated = true
        
        puts "ローソク足更新: #{current_minute.strftime('%H:%M')} 価格変化 #{old_close.round(5)} → #{current_price.round(5)}"
      else
        puts "同一価格のためローソク足更新スキップ: #{current_minute.strftime('%H:%M')} 価格=#{current_price}"
      end
    else
      # 時間が逆行している場合の警告
      puts "警告: 時間が逆行 - 前回: #{last_minute.strftime('%H:%M')}, 現在: #{current_minute.strftime('%H:%M')}"
    end
  end
  
  # 古いデータの削除（メモリ効率のため）
  if @candles.length > 1000
    @candles.shift
    candles_updated = true
  end
  
  # **重要な修正**: 新しいローソク足が追加された場合は必ずMA再計算
  if candles_updated
    # インジケーターを更新
    old_fast_ma = @indicator_calculator.value(:fast_ma)
    old_slow_ma = @indicator_calculator.value(:slow_ma)
    
    # 強制的にMA再計算
    @indicator_calculator.set_candles(@candles)
    
    # MA計算結果の確認
    new_fast_ma = @indicator_calculator.value(:fast_ma)
    new_slow_ma = @indicator_calculator.value(:slow_ma)
    
    puts "=== MA更新確認 ==="
    puts "ローソク足数: #{@candles.length} (更新フラグ: #{candles_updated})"
    puts "FastMA: #{old_fast_ma ? old_fast_ma.round(5) : 'nil'} → #{new_fast_ma ? new_fast_ma.round(5) : 'nil'}"
    puts "SlowMA: #{old_slow_ma ? old_slow_ma.round(5) : 'nil'} → #{new_slow_ma ? new_slow_ma.round(5) : 'nil'}"
    
    # 最新数本のローソク足を表示
    if @candles.size >= 3
      puts "最新3本のローソク足:"
      @candles.last(3).each_with_index do |candle, i|
        puts "  #{i+1}: #{candle[:time].strftime('%H:%M')} OHLC(#{candle[:open].round(5)}/#{candle[:high].round(5)}/#{candle[:low].round(5)}/#{candle[:close].round(5)})"
      end
    end
    puts "===================="
  end
end

        # トレンド判定
        def determine_trend
          # 十分なデータがない場合
          return :none if @candles.length < 15
          
          # 移動平均の値を取得
          fast_ma_current = @indicator_calculator.value(:fast_ma)
          fast_ma_prev = @indicator_calculator.previous_value(:fast_ma, 1)
          slow_ma_current = @indicator_calculator.value(:slow_ma)
          slow_ma_prev = @indicator_calculator.previous_value(:slow_ma, 1)

          if @debug_mode
            puts "=== トレンド判定詳細 ==="
            puts "ローソク足数: #{@candles.length}"
            puts "FastMA現在: #{fast_ma_current ? fast_ma_current.round(6) : 'nil'}, 前回: #{fast_ma_prev ? fast_ma_prev.round(6) : 'nil'}"
            puts "SlowMA現在: #{slow_ma_current ? slow_ma_current.round(6) : 'nil'}, 前回: #{slow_ma_prev ? slow_ma_prev.round(6) : 'nil'}"
          end

          # MA値がnilの場合はエントリーしない
          if fast_ma_current.nil? || fast_ma_prev.nil? || 
            slow_ma_current.nil? || slow_ma_prev.nil?
            if @debug_mode
              puts "MA値がnilのためエントリーなし"
              puts "  FastMA nil?: 現在=#{fast_ma_current.nil?}, 前回=#{fast_ma_prev.nil?}"
              puts "  SlowMA nil?: 現在=#{slow_ma_current.nil?}, 前回=#{slow_ma_prev.nil?}"
            end
            return :none  # エントリーなし
          end

          # 値の有効性チェック（NaNや無限大をチェック）
          unless [fast_ma_current, fast_ma_prev, slow_ma_current, slow_ma_prev].all? { |v| v.is_a?(Numeric) && v.finite? }
            if @debug_mode
              puts "MA値が無効のためエントリーなし"
            end
            return :none
          end

          # MT4と同じ判定ロジック
          if fast_ma_current > slow_ma_current && fast_ma_prev > slow_ma_prev
            if @debug_mode
              puts "トレンド判定: 買い (FastMA > SlowMA)"
              puts "  現在: #{fast_ma_current.round(6)} > #{slow_ma_current.round(6)}"
              puts "  前回: #{fast_ma_prev.round(6)} > #{slow_ma_prev.round(6)}"
            end
            return :buy
          else
            if @debug_mode
              puts "トレンド判定: 売り (FastMA <= SlowMA)"
              puts "  現在: #{fast_ma_current.round(6)} <= #{slow_ma_current.round(6)}" if fast_ma_current && slow_ma_current
              puts "  前回: #{fast_ma_prev.round(6)} <= #{slow_ma_prev.round(6)}" if fast_ma_prev && slow_ma_prev
            end
            return :sell
          end
        end

        def open_first_position(tick, type)
          lot_size = calculate_lot_size
          # エントリー理由を追加
          entry_reason = get_entry_reason(type)
          # ポジションを作成
          position = {
            ticket: generate_ticket_id,
            type: type,
            open_time: tick[:time],
            open_price: type == :buy ? tick[:close] : tick[:close],
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
          # トレード追跡用の記録を残す - ここを追加
          @orders_in_progress ||= []
          @orders_in_progress << position.dup

          # 次のポジションのための価格レベル設定
          if type == :buy
            @state[:buy_rate] = position[:open_price]
            @state[:sell_rate] = @state[:buy_rate] - (@params[:GapProfit] / @params[:SpredKeisuu])
            @state[:next_order] = 2  # 次は売り
          else
            @state[:sell_rate] = position[:open_price]
            @state[:buy_rate] = @state[:sell_rate] + (@params[:GapProfit] / @params[:SpredKeisuu])
            @state[:next_order] = 1  # 次は買い
          end
          
          # MT4版同様、次の指値注文をセット
          prepare_next_stop_order(type)
          
          # MT4版と同じく、最初のポジション作成後に価格レベルを更新
          @state[:first_order] = type == :buy ? 1 : 2
          @state[:first_rate] = position[:open_price]
          @state[:first_lots] = position[:lot_size]
          
          # 次の注文のための初期カウンタ設定
          @state[:next_icount] = 0
          
          # ポジション状態の更新を確実に行う
          update_position_state

          return position
        end

        def prepare_next_stop_order(type)
          # 次のポジションのための指値注文を設定（記録のみ）
          next_type = type == :buy ? :sell : :buy
          next_price = next_type == :buy ? @state[:buy_rate] : @state[:sell_rate]
          next_lot = calculate_next_lot_size
          
          @pending_orders = [{
            type: next_type,
            price: next_price,
            lot_size: next_lot,
            stop_order: true,  # 指値注文フラグ
            created_at: Time.now
          }]
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

          # 係数の確認
          if @debug_mode
            puts "計算されたlot_coefficient: #{lot_coefficient}"
          end

          lot_array = Array.new(positions, 0.0)
          total_lots = 0.0
          syokokin_lot = 0.0
          best_start_lot = start_lot
          
          # 資金計算を修正（絶対値で計算）
          available_balance = @account_info[:balance]
          loss_cut_buffer = [@params[:LosCutProfit].abs, @params[:LosCutPlus].abs * (@params[:fukuri] - 1)].sum
          
          # 利用可能資金を適正に計算（8割程度に制限）
          sikin = (available_balance - loss_cut_buffer) * 0.8
          
          if @debug_mode
            puts "利用可能残高: ¥#{available_balance}"
            puts "ロスカットバッファ: ¥#{loss_cut_buffer}"
            puts "計算用資金: ¥#{sikin}"
          end
          
          # 資金が不足している場合は最小ロットを返す
          if sikin <= 0
            puts "計算用資金不足のため最小ロット(0.01)を返します" if @debug_mode
            return 0.01
          end

          yojyou_syokokin = 0.0
          hituyou_syokokin = 0.0
          
          # 現在の価格を取得
          current_price = @candles.last ? @candles.last[:close] : 1.25
          
          # 証拠金計算を簡略化（より現実的な値に）
          margin_per_lot = current_price * 100000 * 0.04 * (@params[:USDJPY_rate] || 154.5) / 100
          
          if @debug_mode
            puts "証拠金要件/ロット: ¥#{margin_per_lot.round(2)}"
            puts "ロット係数: #{lot_coefficient}"
            puts "シキン（計算用資金）: ¥#{sikin}"
          end

          # MT4と同じロット探索アルゴリズム（範囲を制限）
          test_iterations = 0
          max_test_lot = [max_lot, sikin / margin_per_lot / 10].min  # 現実的な上限を設定

          (1...(max_test_lot * 100).to_i + 1).each do |i|
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
              next_lot = (lot_array[j-1] * lot_coefficient + @params[:keisu_plus_pips])

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

            # デバッグ出力（テスト初期のみ）
            if @debug_mode && test_start_lot <= 0.05
              lots_str = lot_array.map { |l| sprintf("%.2f", l) }.join(', ')
              puts "テスト[#{test_iterations}] lot:#{test_start_lot} - ロット配列:[#{lots_str}]"
              puts "  totalLots:#{total_lots.round(2)}, syokokinLot:#{syokokin_lot.round(2)}"
            end

            # MT4と同じ証拠金計算
            yojyou_syokokin = sikin - (syokokin_lot * margin_per_lot)
            hituyou_syokokin = total_lots * margin_per_lot

            # デバッグ出力（テスト初期のみ）
            if @debug_mode && test_start_lot <= 0.05
              puts "  余剰証拠金: ¥#{yojyou_syokokin.round(2)}, 必要証拠金: ¥#{hituyou_syokokin.round(2)}"
              puts "  条件: #{yojyou_syokokin.round(2)} >= #{hituyou_syokokin.round(2)} ?: #{yojyou_syokokin >= hituyou_syokokin}"
            end
            
            # MT4と同じ判定ロジック
            if max_lot_flag == 1
              if @debug_mode && test_start_lot <= 0.05
                puts "  結果: 最大ロット超過のため中断"
              end
              break
            elsif yojyou_syokokin >= hituyou_syokokin
              best_start_lot = test_start_lot
              if @debug_mode && test_start_lot <= 0.05
                puts "  結果: このロットは可能 (best更新: #{best_start_lot})"
              end
            else
              if @debug_mode && test_start_lot <= 0.05
                puts "  結果: 証拠金不足のため中断"
              end
              break
            end
          end
          
          if @debug_mode
            puts "テスト回数: #{test_iterations}"
            puts "計算された初期ロット: #{best_start_lot}"
          end
          
          # 0.05を超える場合の調整（MT4パラメータに合わせる）
          adjusted_lot = best_start_lot
          if best_start_lot > 0.05
            adjusted_lot = best_start_lot - @params[:MinusLot]
            if @debug_mode
              puts "調整後の初期ロット: #{adjusted_lot}"
            end
          end

          return [adjusted_lot, 0.01].max  # 最小値は0.01
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
        
def check_additional_positions(tick)
  return if @positions.empty?
  
  puts "=== 追加ポジション判定開始 ==="
  puts "現在のポジション数: #{@positions.size}"
  puts "現在価格: #{tick[:close]}"
  
  # MT4版のNextJob()と同じロジック
  # 最初のポジション情報を取得
  first_pos = @positions.first
  puts "最初のポジション: #{first_pos[:type]} @ #{first_pos[:open_price]} (#{first_pos[:lot_size]}ロット)"
  
  if first_pos[:type] == :buy
    @state[:first_order] = 1
    @state[:buy_rate] = first_pos[:open_price]
    @state[:sell_rate] = @state[:buy_rate] - (@params[:GapProfit] / @params[:SpredKeisuu])
  else
    @state[:first_order] = 2
    @state[:sell_rate] = first_pos[:open_price]
    @state[:buy_rate] = @state[:sell_rate] + (@params[:GapProfit] / @params[:SpredKeisuu])
  end
  
  puts "buy_rate: #{@state[:buy_rate]}, sell_rate: #{@state[:sell_rate]}"
  
  # 次の注文タイプを決定
  if @positions.size == 1
    @state[:next_order] = @state[:first_order] == 1 ? 2 : 1
    puts "初回追加注文タイプ設定: #{@state[:next_order]} (1=買い, 2=売り)"
    
    # 新しい注文レベルなので該当フラグのみリセット
    if @state[:next_order] == 1
      @buy_order_executed = false
      puts "買い注文フラグをリセット"
    else
      @sell_order_executed = false
      puts "売り注文フラグをリセット"
    end
  end
  
  # 価格到達チェック（約定フラグで制御）
  if @state[:next_order] == 1  # 次は買い
    puts "買い注文チェック: 価格#{tick[:close]} <= 指値#{@state[:buy_rate]} ? #{tick[:close] <= @state[:buy_rate]}"
    puts "買い約定済み?: #{@buy_order_executed}"
    
    if tick[:close] <= @state[:buy_rate] && !@buy_order_executed
      next_lot = calculate_next_lot_size
      puts "買い注文条件チェック:"
      puts "  総ロット制限: #{@state[:all_lots]} + #{next_lot} < #{@params[:lot_seigen]} ? #{@state[:all_lots] + next_lot < @params[:lot_seigen]}"
      puts "  ポジション数制限: #{@positions.size} < #{@params[:lot_pos_seigen]} ? #{@positions.size < @params[:lot_pos_seigen]}"
      
      if @state[:all_lots] + next_lot < @params[:lot_seigen] && 
        @positions.size < @params[:lot_pos_seigen]
        
        puts "買い約定実行: 価格=#{tick[:close]}, 指値=#{@state[:buy_rate]}, ロット=#{next_lot}"
        
        add_position(tick, :buy)
        @buy_order_executed = true  # 約定フラグを立てる
        # 次の売りレベルを設定
        @state[:next_order] = 2
        adjust_gap_for_next_position
      else
        puts "買い注文制限により実行せず"
      end
    else
      puts "買い注文条件不成立"
    end
  elsif @state[:next_order] == 2  # 次は売り
    puts "売り注文チェック: 価格#{tick[:close]} >= 指値#{@state[:sell_rate]} ? #{tick[:close] >= @state[:sell_rate]}"
    puts "売り約定済み?: #{@sell_order_executed}"
    
    if tick[:close] >= @state[:sell_rate] && !@sell_order_executed
      next_lot = calculate_next_lot_size
      puts "売り注文条件チェック:"
      puts "  総ロット制限: #{@state[:all_lots]} + #{next_lot} < #{@params[:lot_seigen]} ? #{@state[:all_lots] + next_lot < @params[:lot_seigen]}"
      puts "  ポジション数制限: #{@positions.size} < #{@params[:lot_pos_seigen]} ? #{@positions.size < @params[:lot_pos_seigen]}"
      
      if @state[:all_lots] + next_lot < @params[:lot_seigen] && 
        @positions.size < @params[:lot_pos_seigen]
        
        puts "売り約定実行: 価格=#{tick[:close]}, 指値=#{@state[:sell_rate]}, ロット=#{next_lot}"
        
        add_position(tick, :sell)
        @sell_order_executed = true  # 約定フラグを立てる
        # 次の買いレベルを設定
        @state[:next_order] = 1
        adjust_gap_for_next_position
      else
        puts "売り注文制限により実行せず"
      end
    else
      puts "売り注文条件不成立"
    end
  end
  
  puts "=== 追加ポジション判定終了 ===\n"
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
            next_lot = @positions.first[:lot_size] * @params[:next_order_keisu] + @params[:keisu_plus_pips]
            
            # デバッグ出力
            #puts "次のロット計算(初回): #{@positions.first[:lot_size]} * #{@params[:next_order_keisu]} + #{@params[:keisu_plus_pips]} = #{next_lot}" if @debug_mode
          else
            # 2回目以降の追加ポジション
            last_pos = @positions.last
            next_lot = last_pos[:lot_size] * @params[:next_order_keisu]
            
            # position_xより大きい場合はロットサイズを調整
            if @positions.size >= @params[:position_x]
              profit_zz_total = (@positions.size - @params[:position_x]) * @params[:Profit_down_Percent]
              lot_adjust_rate = 1.0 + (profit_zz_total / 100.0)
              keisu_plus = @params[:keisu_plus_pips] * @positions.size
              
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
            @lot_keisu_plus = @params[:keisu_plus_pips] * @positions.size
            
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
          return if @positions.empty?
          
          # 総損益計算（円建て）
          total_profit_jpy = 0
          @positions.each do |pos|
            profit_jpy = calculate_position_profit(pos, tick, :JPY)
            total_profit_jpy += profit_jpy
          end
          
          # ロスカット判定（ポジション数に関係なく常にチェック）
          if @positions.size >= @params[:LosCutPosition]
            loss_cut_profit_jpy = @params[:LosCutProfit] + 
                                  (@params[:LosCutPlus] * (@params[:fukuri] - 1))
            
            if total_profit_jpy < loss_cut_profit_jpy
              puts "ロスカット実行: #{total_profit_jpy}円 < #{loss_cut_profit_jpy}円" if @debug_mode
              all_delete(tick)
              return
            end
          end
          
          # 利益確定チェック（最後のポジションのみ）
          profit_pips = @params[:Takeprofit]
          
          if @positions.size > @params[:position_x]
            profit_zz_total = (@positions.size - @params[:position_x]) * @params[:Profit_down_Percent]
            profit_pips = @params[:Takeprofit] * (1 - (profit_zz_total / 100.0))
          end
          
          last_pos = @positions.last
          current_profit_pips = calculate_position_profit(last_pos, tick, :pips)
          
          if current_profit_pips >= profit_pips
            start_trailing_stop(tick)
          end
        end

        def calculate_position_profit(position, tick, return_currency = :JPY)
          lot_size = position[:lot_size]
          contract_size = 100000  # 1ロット = 10万通貨
          
          # 単純な価格差計算（MT4と同じ）
          if position[:type] == :buy
            price_diff = tick[:close] - position[:open_price]
          else
            price_diff = position[:open_price] - tick[:close]
          end
          
          # ドル建て利益
          usd_profit = price_diff * lot_size * contract_size
          
          # 円建て利益
          jpy_profit = usd_profit * (@params[:USDJPY_rate] || 155.0)
          
          # pips計算用（利益確認で使用）
          if return_currency == :pips
            return price_diff * @params[:SpredKeisuu]
          end
          
          return return_currency == :USD ? usd_profit : jpy_profit
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

          # profit は円建てで計算されているため、USD 利益は別途算出する
          profit_jpy = profit
          profit_usd = calculate_position_profit(position, tick, :USD)
          
          # トレード記録に通貨単位情報を追加
          trade = position.merge(
            close_time: tick[:time],
            close_price: tick[:close],
            profit: profit_usd,      # USD単位で保存
            profit_jpy: profit_jpy,  # JPY単位も保存
            currency: "JPY",         # 明示的に通貨単位を記録
            position_count: @positions.size,
            exit_reason: get_exit_reason(position, tick)
          )

          @orders << trade
          #@total_profit += profit
          @total_profit += profit_usd  # 集計は一貫してUSDで
          # アカウント情報の残高を更新
          @account_info[:balance] += profit

  if @debug_mode
  # 残高更新のデバッグ出力
    puts "【ポジション決済】#{position[:type]}, Lot: #{position[:lot_size]}"
    puts "ポジションタイプ: #{position[:type]}"
    puts "利益: $#{profit_usd} (¥#{profit_jpy})"
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
          
          if @positions.size >= @params[:LosCutPosition]
            total_profit_jpy = 0  # 円建てで計算
            
            @positions.each do |pos|
              # 円建てで利益を計算
              profit_jpy = calculate_position_profit(pos, tick, :JPY)
              total_profit_jpy += profit_jpy
            end
            
            # ロスカット閾値（円建て）
            loss_cut_profit_jpy = @params[:LosCutProfit] + (@params[:LosCutPlus] * (@params[:fukuri] - 1))
            
            if total_profit_jpy < loss_cut_profit_jpy
              puts "ロスカット実行: 総損益 #{total_profit_jpy}円 < 閾値 #{loss_cut_profit_jpy}円" if @debug_mode
              @loss_cut_flag = 1
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
            
          # MT4コードと同じ条件分岐（一回目の調整）
          if lot < 0.01
            lot = 0.01
          elsif lot > 0.05
            lot -= @params[:MinusLot]
          end
          
          # 二回目の調整（MT4のバグを正確に再現）
          if lot < 0.01
            puts "最小ロット制限により0.01に調整"
            lot = 0.01
          elsif lot > 0.05
            puts "ロット調整: #{lot} → #{lot - @params[:MinusLot]}"
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
          @first_entry_done = false  # ポジション全削除時にフラグをリセット
          puts "すべてのポジションをクローズしました" if @debug_mode
        end

        # 最大ドローダウン更新
        def update_max_drawdown
          return if @balance_history.empty?

          current_balance = @balance_history.last
          @peak_balance = current_balance if current_balance > @peak_balance

          drawdown = @peak_balance - current_balance
          @max_drawdown = drawdown if drawdown > @max_drawdown
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

      end
    end
  end
end
