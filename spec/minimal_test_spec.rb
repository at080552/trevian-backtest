require 'rspec'

RSpec.describe "最小限のテスト" do
  it "真は真である" do
    expect(true).to eq(true)
  end
  
  it "1+1は2である" do
    expect(1+1).to eq(2)
  end
end
