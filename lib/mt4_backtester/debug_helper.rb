module MT4Backtester
  module DebugHelper
    def self.debug_enabled?
      ENV['DEBUG'] == '1'
    end
    
    def self.debug(message)
      puts "[DEBUG] #{message}" if debug_enabled?
    end
  end
end
