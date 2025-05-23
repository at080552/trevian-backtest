require_relative '../helpers/spec_helper'
require "tmpdir"

RSpec.describe MT4Backtester::Data::TickDataFactory do
  describe '.create_loader' do
    around do |example|
      Dir.mktmpdir do |dir|
        @tmp_dir = dir
        example.run
      end
    end

    it 'returns CsvTickData for .csv files' do
      file = File.join(@tmp_dir, 'test.csv')
      File.write(file, "sample")
      loader = described_class.create_loader(file)
      expect(loader).to be_a(MT4Backtester::Data::CsvTickData)
    end

    it 'returns FxtTickData for .fxt files' do
      file = File.join(@tmp_dir, 'test.fxt')
      File.write(file, "sample")
      loader = described_class.create_loader(file)
      expect(loader).to be_a(MT4Backtester::Data::FxtTickData)
    end

    it 'returns HistdataTickData for histdata compressed files' do
      file = File.join(@tmp_dir, 'histdata_EURUSD_202001.csv.gz')
      File.write(file, "sample")
      loader = described_class.create_loader(file)
      expect(loader).to be_a(MT4Backtester::Data::HistdataTickData)
    end
  end
end
