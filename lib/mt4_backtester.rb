# MT4 Backtesterのエントリーポイント
require 'json'  # JSONライブラリを明示的にインポート
require 'fileutils'  # FileUtilsを明示的にインポート

# コアモジュール
module MT4Backtester
  module Core; end
  module Data; end
  module Parsers; end
  module Strategies; end
  module Indicators; end
  module Models; end
  module Visualization; end
  
  class << self
    def version
      "0.1.0"
    end
    
    def root
      File.expand_path('..', __dir__)
    end
    
    def logger
      @logger ||= Logger.new(STDOUT)
    end
  end
end

# データ処理モジュール
require_relative 'mt4_backtester/data/tick_data_base'
require_relative 'mt4_backtester/data/csv_tick_data'
require_relative 'mt4_backtester/data/fxt_tick_data'
require_relative 'mt4_backtester/data/histdata_tick_data'
require_relative 'mt4_backtester/data/mt4_tick_data'
require_relative 'mt4_backtester/data/custom_tick_data'
require_relative 'mt4_backtester/data/tick_data_factory'

# インジケーターモジュール
require_relative 'mt4_backtester/indicators/moving_average'
require_relative 'mt4_backtester/indicators/indicator_calculator'
require_relative 'mt4_backtester/indicators/momentum'

# モデルモジュール
require_relative 'mt4_backtester/models/account'

# 戦略モジュール
require_relative 'mt4_backtester/strategies/trevian/core_logic'
require_relative 'mt4_backtester/strategies/trevian_strategy'

# パーサーモジュール
require_relative 'mt4_backtester/parsers/mt4_parser'

# 可視化モジュール
require_relative 'mt4_backtester/visualization/chart_data_processor'
require_relative 'mt4_backtester/visualization/html_chart_generator'

# コアモジュール
require_relative 'mt4_backtester/core/backtester'

require_relative 'mt4_backtester/config/config_loader'
