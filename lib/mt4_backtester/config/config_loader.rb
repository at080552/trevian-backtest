require 'dotenv'

module MT4Backtester
  module Config
    class ConfigLoader
      def self.load
        # .envファイルを読み込む
        Dotenv.load

        # パラメータをハッシュに格納
        {
          Gap: fetch_float('TREVIAN_GAP', 4000.0),
          Takeprofit: fetch_float('TREVIAN_TAKEPROFIT', 60.0),
          Start_Lots: fetch_float('TREVIAN_START_LOTS', 0.95),
          Gap_down_Percent: fetch_float('TREVIAN_GAP_DOWN_PERCENT', 0),
          Profit_down_Percent: fetch_float('TREVIAN_PROFIT_DOWN_PERCENT', 0),
          strategy_test: fetch_int('TREVIAN_STRATEGY_TEST', 0),
          Start_Sikin: fetch_int('TREVIAN_START_SIKIN', 300),
          MinusLot: fetch_float('TREVIAN_MINUS_LOT', 0.99),
          MaxLotX: fetch_float('TREVIAN_MAX_LOT_X', 100),
          lot_seigen: fetch_float('TREVIAN_LOT_SEIGEN', 100),
          lot_pos_seigen: fetch_int('TREVIAN_LOT_POS_SEIGEN', 30),
          keisu_x: fetch_float('TREVIAN_KEISU_X', 9.9),
          keisu_pulus_pips: fetch_float('TREVIAN_KEISU_PULUS_PIPS', 0.35),
          position_x: fetch_int('TREVIAN_POSITION_X', 1),
          LosCutPosition: fetch_int('TREVIAN_LOSCUT_POSITION', 15),
          LosCutProfit: fetch_float('TREVIAN_LOSCUT_PROFIT', -900),
          LosCutPlus: fetch_float('TREVIAN_LOSCUT_PLUS', -40),
          trailLength: fetch_int('TREVIAN_TRAIL_LENGTH', 99)
        }
      end

      private

      # 環境変数を数値（Float）として取得
      def self.fetch_float(key, default = nil)
        value = ENV[key]
        value ? value.to_f : default
      end

      # 環境変数を整数（Integer）として取得
      def self.fetch_int(key, default = nil)
        value = ENV[key]
        value ? value.to_i : default
      end
    end
  end
end