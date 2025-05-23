require_relative '../helpers/spec_helper'

RSpec.describe 'JPY account balance handling' do
  it 'updates balances with JPY profits' do
    strategy = MT4Backtester::Strategies::TrevianStrategy.new({Start_Sikin: 100_000, USDJPY_rate: 155.0})

    trades = [
      {
        open_time: Time.new(2023,1,1,0,0),
        close_time: Time.new(2023,1,1,1,0),
        open_price: 1.0,
        close_price: 1.1,
        lot_size: 1.0,
        type: :buy,
        profit: 100.0,
        profit_jpy: 15_500.0,
        currency: 'JPY'
      },
      {
        open_time: Time.new(2023,1,1,2,0),
        close_time: Time.new(2023,1,1,3,0),
        open_price: 1.0,
        close_price: 0.9,
        lot_size: 1.0,
        type: :sell,
        profit: -50.0,
        profit_jpy: -7_750.0,
        currency: 'JPY'
      }
    ]

    results = { trades: trades, params: strategy.params }
    strategy.instance_variable_set(:@results, results)
    strategy.send(:enhance_trade_records)

    tick_data = [
      {time: trades.first[:open_time], open:1, high:1, low:1, close:1, volume:1},
      {time: trades.last[:close_time], open:1, high:1, low:1, close:1, volume:1}
    ]

    processor = MT4Backtester::Visualization::ChartDataProcessor.new(strategy.results, tick_data)
    final_balance = processor.equity_curve.last[:balance]

    expect(final_balance).to eq(107_750.0)
  end
end
