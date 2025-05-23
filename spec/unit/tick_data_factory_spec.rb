require_relative '../helpers/spec_helper'
require 'tempfile'

RSpec.describe MT4Backtester::Data::TickDataFactory do
  describe '.create_loader' do
    it 'detects MT4 tick data in large files with long lines' do
      Tempfile.create('mt4_tick') do |file|
        200.times do
          file.puts "20220101 123456789,1.23456,1.23467"
        end
        file.flush
        loader = described_class.create_loader(file.path)
        expect(loader).to be_a(MT4Backtester::Data::MT4TickData)
      end
    end
  end
end

