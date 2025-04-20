module MT4Backtester
  module Models
    class Account
      attr_accessor :balance, :equity, :margin, :free_margin, :margin_level
      attr_reader :initial_deposit, :currency, :leverage, :trades_history
      
      def initialize(initial_deposit = 10000, currency = 'USD', leverage = 100)
        @initial_deposit = initial_deposit
        @balance = initial_deposit
        @equity = initial_deposit
        @margin = 0
        @free_margin = initial_deposit
        @margin_level = 0
        @currency = currency
        @leverage = leverage
        @trades_history = []
      end
      
      def update(positions)
        # ポジションのマージン計算
        calculate_margin(positions)
        
        # 未実現損益計算
        floating_pl = calculate_floating_pl(positions)
        
        # エクイティ計算
        @equity = @balance + floating_pl
        
        # 余剰証拠金計算
        @free_margin = @equity - @margin
        
        # 証拠金レベル計算
        @margin_level = @margin > 0 ? (@equity / @margin) * 100 : 0
      end
      
      def add_trade(trade)
        @trades_history << trade
        @balance += trade[:profit]
        update([])  # 残りのポジションがゼロと仮定
      end
      
      def calculate_margin(positions)
        @margin = 0
        
        positions.each do |pos|
          # 各通貨ペアに対する適切な証拠金率を適用
          # ここでは簡略化
          contract_size = 100000  # 標準的なロットサイズ（1ロット = 10万通貨）
          @margin += (pos[:open_price] * pos[:lot_size] * contract_size) / @leverage
        end
      end
      
      def calculate_floating_pl(positions)
        floating_pl = 0
        
        positions.each do |pos|
          # 未実現損益の計算
          price_diff = pos[:current_price] - pos[:open_price]
          
          # 買いと売りで計算が異なる
          multiplier = pos[:type] == :buy ? 1 : -1
          
          # ロットサイズに基づいて計算
          contract_size = 100000  # 標準的なロットサイズ
          floating_pl += price_diff * multiplier * pos[:lot_size] * contract_size
        end
        
        floating_pl
      end
      
      def get_summary
        {
          initial_deposit: @initial_deposit,
          current_balance: @balance,
          current_equity: @equity,
          profit_loss: @balance - @initial_deposit,
          profit_percent: ((@balance - @initial_deposit) / @initial_deposit) * 100,
          max_drawdown: calculate_max_drawdown,
          total_trades: @trades_history.size,
          winning_trades: @trades_history.count { |t| t[:profit] > 0 },
          losing_trades: @trades_history.count { |t| t[:profit] <= 0 }
        }
      end
      
      def calculate_max_drawdown
        max_balance = @initial_deposit
        max_drawdown = 0
        
        running_balance = @initial_deposit
        
        @trades_history.each do |trade|
          running_balance += trade[:profit]
          
          if running_balance > max_balance
            max_balance = running_balance
          end
          
          drawdown = max_balance - running_balance
          max_drawdown = drawdown if drawdown > max_drawdown
        end
        
        max_drawdown
      end
    end
  end
end
