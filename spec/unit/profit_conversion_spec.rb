require_relative '../helpers/spec_helper'

RSpec.describe MT4Backtester::Strategies::Trevian::CoreLogic do
  it 'records USD and JPY profit separately' do
    params = {
      Start_Sikin: 100_000,
      USDJPY_rate: 100.0,
      Symbol: 'GBPUSD'
    }
    core = described_class.new(params)

    position = {
      type: :buy,
      lot_size: 1.0,
      open_time: Time.new(2023,1,1,0,0),
      open_price: 1.1
    }
    tick = { time: Time.new(2023,1,1,1,0), close: 1.2 }

    core.close_position(position, tick)
    trade = core.instance_variable_get(:@orders).last

    expect(trade[:profit_jpy]).to be_within(0.01).of(1_000_000.0)
    expect(trade[:profit]).to be_within(0.01).of(10_000.0)
    expect(trade[:currency]).to eq('JPY')
  end
end
