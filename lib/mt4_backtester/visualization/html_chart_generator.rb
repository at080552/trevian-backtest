require 'json'  # JSONライブラリを明示的にインポート

module MT4Backtester
  module Visualization
    class HtmlChartGenerator
      def initialize(chart_data)
        @chart_data = chart_data
      end
      
      def generate_html(title = 'Trevian Backtest Results')
        html = <<-HTML
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>#{title}</title>
  <!-- Chart.js 本体（既にある） -->
  <script src="https://cdn.jsdelivr.net/npm/chart.js@4"></script>
  <!-- 追加：zoom プラグイン -->
  <script src="https://cdn.jsdelivr.net/npm/chartjs-plugin-zoom@2"></script>
  <script src="https://cdn.jsdelivr.net/npm/chartjs-adapter-date-fns"></script>

  <script>
    Chart.register(window.ChartZoom);   // ← ChartZoom で OK
  </script>

  <style>
    body {
      font-family: Arial, sans-serif;
      margin: 20px;
      background-color: #f5f5f5;
    }
    .container {
      max-width: 1200px;
      margin: 0 auto;
      background-color: white;
      padding: 20px;
      border-radius: 8px;
      box-shadow: 0 2px 4px rgba(0,0,0,0.1);
    }
    .chart-container {
      position: relative;
      height: 400px;
      margin-bottom: 30px;
    }
    .header {
      text-align: center;
      margin-bottom: 20px;
    }
    .stats-container {
      display: flex;
      flex-wrap: wrap;
      gap: 15px;
      margin-bottom: 20px;
    }
    .stat-box {
      flex: 1;
      min-width: 200px;
      padding: 15px;
      background-color: #f8f9fa;
      border-radius: 6px;
      box-shadow: 0 1px 3px rgba(0,0,0,0.1);
    }
    .stat-title {
      font-weight: bold;
      margin-bottom: 5px;
      color: #555;
    }
    .stat-value {
      font-size: 24px;
      font-weight: bold;
      color: #333;
    }
    .positive { color: #28a745; }
    .negative { color: #dc3545; }
    .neutral { color: #6c757d; }
    table {
      width: 100%;
      border-collapse: collapse;
      margin-bottom: 20px;
    }
    th, td {
      padding: 8px 12px;
      text-align: left;
      border-bottom: 1px solid #ddd;
    }
    th {
      background-color: #f2f2f2;
    }
    tr:hover {
      background-color: #f5f5f5;
    }
    .parameters-container {
      margin-top: 20px;
      margin-bottom: 30px;
      background-color: #f8f9fa;
      border-radius: 6px;
      padding: 15px;
      box-shadow: 0 1px 3px rgba(0,0,0,0.1);
    }
    .parameters-title {
      font-size: 18px;
      font-weight: bold;
      margin-bottom: 10px;
      color: #333;
    }
    .parameters-grid {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(250px, 1fr));
      gap: 10px;
    }
    .parameter-item {
      display: flex;
      justify-content: space-between;
      padding: 5px 0;
      border-bottom: 1px dashed #ddd;
    }
    .parameter-name {
      font-weight: bold;
      color: #555;
    }
    .parameter-value {
      color: #333;
    }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>#{title}</h1>
      <p>期間: #{format_time_range}</p>
    </div>
    
    <div class="parameters-container">
      <div class="parameters-title">主要パラメータ</div>
      <div class="parameters-grid">
        #{generate_parameters_html}
      </div>
    </div>

    <div class="stats-container">
      #{generate_stats_html}
    </div>

    <div class="indicator-controls">
    <h3>テクニカル指標</h3>
    <div class="checkbox-group">
      <label><input type="checkbox" id="showFastMA" checked> 短期MA(5)</label>
      <label><input type="checkbox" id="showSlowMA" checked> 長期MA(14)</label>
      <label><input type="checkbox" id="showMomentum"> モメンタム(20)</label>
    </div>
  </div>

    <div class="chart-container">
      <canvas id="priceChart"></canvas>
    </div>

    <button id="resetZoom">ズームをリセット</button>
    <script>
      document.getElementById('resetZoom')
              .addEventListener('click', () => priceChart.resetZoom());
    </script>

    <div class="chart-container">
      <canvas id="equityChart"></canvas>
    </div>
    
    #{generate_trades_table_html}
  </div>

  <script>
  //価格チャートの設定
  const priceCtx = document.getElementById('priceChart').getContext('2d');
  const priceChart = new Chart(priceCtx, {
    type: 'line',
    data: {
      datasets: [
        {
          label: '価格',
          data: #{price_data_json},
          borderColor: 'rgb(75, 192, 192)',
          tension: 0.1,
          pointRadius: 0,
          borderWidth: 1,
          yAxisID: 'y'
        },
        #{generate_indicator_datasets},
        #{generate_trade_points_datasets}
      ]
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      interaction: {
        intersect: false,
        mode: 'index'  // ホバー時に垂直線を表示
      },
      scales: {
        x: {
          type: 'time',
          time: {
            unit: 'day',
            displayFormats: {
              day: 'yyyy-MM-dd'
            }
          },
          title: {
            display: true,
            text: '日付'
          },
          grid: {
          color: 'rgba(200, 200, 200, 0.2)'  // グリッド線を薄く
          }
        },
        y: {
          title: {
            display: true,
            text: '価格'
          },
          position: 'left',
          grid: {
            color: 'rgba(200, 200, 200, 0.2)'  // グリッド線を薄く
          }
        },
        y2: {
          title: {
            display: true,
            text: 'テクニカル指標'
          },
          position: 'right',
          grid: {
            drawOnChartArea: false
          }
        }
      },
      plugins: {
        zoom: {
          zoom: {                      // ← 拡大（wheel / pinch）
            wheel: { enabled: true, modifierKey: 'ctrl' }, // Ctrl+ホイールでズーム
            pinch: { enabled: true },                     // モバイル pinch
            mode: 'x',                                    // 'x' 方向だけ、必要なら 'xy'
            overScaleMode: 'y',                           // マウス位置が指標側でもズーム
          },
          pan: {                        // ← ドラッグでスクロール
            enabled: true,
            mode: 'x',
            onPanStart: ({chart}) => {
              console.log('pan start', chart); // pan 開始時に表示
            },
            onPanComplete: ({chart}) => {
              console.log('pan end', chart);   // 完了時にも表示（任意）
            },
            modifierKey: 'shift'        // Shift+ドラッグでパン
          },
          limits: {                     // ← ズームし過ぎを防ぐ
            x: { min: 'original', max: 'original' },
            y: { min: 'original', max: 'original' }
          }
        },
        title: {
          display: true,
          text: '価格チャートとテクニカル指標'
        },
        legend: {
          position: 'top',
          labels: {
            padding: 10,
            usePointStyle: true  // 凡例のポイントスタイルを改善
          }
        },
        tooltip: {
          callbacks: {
            label: function(context) {
              const dataset = context.dataset;
              if (dataset.tradeData) {
                const point = dataset.tradeData[context.dataIndex];
                if (point) {
                  let label = `${point.action === 'entry' ? 'エントリー' : '決済'} (${point.type === 'buy' ? '買い' : '売り'})`;
                  label += ` - ロット: ${point.lot}`;
                  if (point.profit) label += ` - 利益: $${point.profit.toFixed(2)}`;
                  if (point.reason) label += ` - 理由: ${point.reason}`;
                  return label;
                }
              }
              if (dataset.type === 'line' && dataset.label.includes('MA')) {
                return `${dataset.label}: ${context.parsed.y.toFixed(5)}`;
              }
              return `${dataset.label}: ${context.parsed.y}`;
            }
          }
        }
      }
    }
  });

    // 資産チャートの設定
    const equityCtx = document.getElementById('equityChart').getContext('2d');
    const equityChart = new Chart(equityCtx, {
      type: 'line',
      data: {
        datasets: [
          {
            label: '残高',
            data: #{equity_data_json},
            borderColor: 'rgb(54, 162, 235)',
            backgroundColor: 'rgba(54, 162, 235, 0.1)',
            fill: true,
            tension: 0.1
          },
          {
            label: 'ドローダウン',
            data: #{drawdown_data_json},
            borderColor: 'rgb(255, 99, 132)',
            backgroundColor: 'rgba(255, 99, 132, 0.1)',
            fill: true,
            tension: 0.1,
            yAxisID: 'y2'
          }
        ]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        scales: {
          x: {
            type: 'time',
            time: {
              unit: 'day',
              displayFormats: {
                day: 'yyyy-MM-dd'
              }
            },
            title: {
              display: true,
              text: '日付'
            }
          },
          y: {
            title: {
              display: true,
              text: '残高 ($)'
            },
            beginAtZero: false
          },
          y2: {
            position: 'right',
            title: {
              display: true,
              text: 'ドローダウン ($)'
            },
            beginAtZero: true,
            reverse: true,
            grid: {
              drawOnChartArea: false
            }
          }
        },
        plugins: {
          title: {
            display: true,
            text: '資産推移とドローダウン'
          }
        }
      }
    });
    </script>

    <script>
    // インジケーター表示切り替え用のJavaScript
    document.getElementById('showFastMA').addEventListener('change', function() {
      const dataset = priceChart.data.datasets.find(d => d.label === '短期MA(5)');
      if (dataset) {
        dataset.hidden = !this.checked;
        priceChart.update();
      }
    });
    
    document.getElementById('showSlowMA').addEventListener('change', function() {
      const dataset = priceChart.data.datasets.find(d => d.label === '長期MA(14)');
      if (dataset) {
        dataset.hidden = !this.checked;
        priceChart.update();
      }
    });
    
    document.getElementById('showMomentum').addEventListener('change', function() {
      const dataset = priceChart.data.datasets.find(d => d.label === 'モメンタム(20)');
      if (dataset) {
        dataset.hidden = !this.checked;
        priceChart.update();
      }
    });
  </script>
  

  </body>
</html>
HTML

        html
      end
      
      private

      def generate_indicator_datasets
        return "" if @chart_data.indicator_data.empty?
        
        datasets = []
        
        # 移動平均線データセット
        if @chart_data.indicator_data[:ma_fast] && !@chart_data.indicator_data[:ma_fast].empty?
          ma_fast_data = JSON.generate(@chart_data.indicator_data[:ma_fast].map do |point|
            { x: point[:time].strftime('%Y-%m-%d %H:%M'), y: point[:value] }
          end)
          
          datasets << %{
            {
              label: '短期MA(5)',
              data: #{ma_fast_data},
              borderColor: 'rgba(255, 99, 132, 1)',
              borderWidth: 1.5,
              pointRadius: 0,
              tension: 0.1,
              yAxisID: 'y'
            }
          }
        end
        
        if @chart_data.indicator_data[:ma_slow] && !@chart_data.indicator_data[:ma_slow].empty?
          ma_slow_data = JSON.generate(@chart_data.indicator_data[:ma_slow].map do |point|
            { x: point[:time].strftime('%Y-%m-%d %H:%M'), y: point[:value] }
          end)
          
          datasets << %{
            {
              label: '長期MA(14)',
              data: #{ma_slow_data},
              borderColor: 'rgba(54, 162, 235, 1)',
              borderWidth: 1.5,
              pointRadius: 0,
              tension: 0.1,
              yAxisID: 'y'
            }
          }
        end
        
        # モメンタム指標（別のY軸を使用）
        if @chart_data.indicator_data[:momentum] && !@chart_data.indicator_data[:momentum].empty?
          momentum_data = JSON.generate(@chart_data.indicator_data[:momentum].map do |point|
            { x: point[:time].strftime('%Y-%m-%d %H:%M'), y: point[:value] }
          end)
          
          datasets << %{
            {
              label: 'モメンタム(20)',
              data: #{momentum_data},
              borderColor: 'rgba(153, 102, 255, 1)',
              backgroundColor: 'rgba(153, 102, 255, 0.2)',
              borderWidth: 1,
              pointRadius: 0,
              fill: true,
              tension: 0.1,
              yAxisID: 'y2',
              hidden: true
            }
          }
        end
        
        datasets.join(",\n")
      end
      
      def format_time_range
        return "データなし" if @chart_data.price_data.empty?
        
        start_time = @chart_data.price_data.first[:time]
        end_time = @chart_data.price_data.last[:time]
        
        "#{start_time} から #{end_time}"
      end
      
      def generate_parameters_html
        # 主要パラメータの表示
        return "パラメータデータなし" unless @chart_data.results && @chart_data.results[:params]
        
        params = @chart_data.results[:params]
        
        # 主要パラメータのリスト
        important_params = [
          [:Gap, "ギャップ（pips）"],
          [:Takeprofit, "利益確定（pips）"],
          [:Start_Lots, "開始ロット"],
          [:Gap_down_Percent, "ギャップ縮小率（%）"],
          [:Profit_down_Percent, "利益縮小率（%）"],
          [:keisu_x, "注文係数"],
          [:keisu_pulus_pips, "追加pips"],
          [:position_x, "ポジション調整数"],
          [:LosCutPosition, "ロスカットポジション数"],
          [:LosCutProfit, "ロスカット閾値（$）"],
          [:LosCutPlus, "ロスカット追加（$）"],
          [:trailLength, "トレール長さ（pips）"],
          [:MaxLotX, "最大ロット倍率"],
          [:MinusLot, "ロット減少係数"]
        ]
        
        # 計算パラメータ
        calculated_params = {}
        if params[:Gap] && params[:Takeprofit] && params[:keisu_x]
          calculated_params[:next_order_keisu] = ((params[:Gap] + params[:Takeprofit]) / params[:Takeprofit]) * params[:keisu_x]
        end
        
        params_html = ""
        
        # 主要パラメータの表示
        important_params.each do |key, label|
          if params.key?(key)
            params_html += <<-HTML
        <div class="parameter-item">
          <span class="parameter-name">#{label}</span>
          <span class="parameter-value">#{format('%.2f', params[key].to_f)}</span>
        </div>
            HTML
          end
        end
        
        # 計算パラメータの表示
        calculated_params.each do |key, value|
          params_html += <<-HTML
        <div class="parameter-item">
          <span class="parameter-name">次の注文係数</span>
          <span class="parameter-value">#{value.round(2)}</span>
        </div>
          HTML
        end
        
        params_html
      end
      
      def generate_stats_html
        # 統計情報を取得（実際のバックテスト結果から取得する必要あり）
        total_trades = @chart_data.trade_points.size / 2  # エントリー/決済ペアなので2で割る
        winning_trades = @chart_data.trade_points.select { |p| p[:action] == 'exit' && p[:profit] && p[:profit] > 0 }.size
        losing_trades = @chart_data.trade_points.select { |p| p[:action] == 'exit' && p[:profit] && p[:profit] <= 0 }.size
        
        total_profit = @chart_data.trade_points.select { |p| p[:action] == 'exit' && p[:profit] }.sum { |p| p[:profit] || 0 }
        
        # 最大ドローダウン
        max_drawdown = @chart_data.equity_curve.map { |p| p[:drawdown] }.max || 0
        
        # 勝率
        win_rate = total_trades > 0 ? (winning_trades.to_f / total_trades * 100).round(2) : 0
        
        stats_html = <<-HTML
      <div class="stat-box">
        <div class="stat-title">取引回数</div>
        <div class="stat-value neutral">#{total_trades}</div>
      </div>
      <div class="stat-box">
        <div class="stat-title">勝率</div>
        <div class="stat-value #{win_rate >= 50 ? 'positive' : 'negative'}">#{win_rate}%</div>
      </div>
      <div class="stat-box">
        <div class="stat-title">総利益</div>
        <div class="stat-value #{total_profit >= 0 ? 'positive' : 'negative'}">$#{total_profit.round(2)}</div>
      </div>
      <div class="stat-box">
        <div class="stat-title">最大ドローダウン</div>
        <div class="stat-value negative">$#{max_drawdown.round(2)}</div>
      </div>
        HTML
        
        stats_html
      end
      
      def generate_trades_table_html
        return "<p>取引データなし</p>" if @chart_data.trade_points.empty?
        
        # エントリーと決済をペアにする
        entry_points = @chart_data.trade_points.select { |p| p[:action] == 'entry' }
        exit_points = @chart_data.trade_points.select { |p| p[:action] == 'exit' }
        
        # 取引ペアは少ないほうに合わせる
        trade_count = [entry_points.size, exit_points.size].min
        
        table_html = <<-HTML
    <h2>取引履歴</h2>
    <table>
      <thead>
        <tr>
          <th>#</th>
          <th>タイプ</th>
          <th>ロット</th>
          <th>エントリー時間</th>
          <th>エントリー価格</th>
          <th>決済時間</th>
          <th>決済価格</th>
          <th>利益</th>
        </tr>
      </thead>
      <tbody>
        HTML
        
        trade_count.times do |i|
          entry = entry_points[i]
          exit = exit_points[i]
          
          profit = exit[:profit] || 0
          profit_class = profit > 0 ? 'positive' : (profit < 0 ? 'negative' : 'neutral')
          
          table_html += <<-HTML
        <tr>
          <td>#{i + 1}</td>
          <td>#{entry[:type] == 'buy' ? '買い' : '売り'}</td>
          <td>#{format('%.2f', entry[:lot].to_f)}</td>
          <td>#{entry[:time]}</td>
          <td>#{entry[:price]}</td>
          <td>#{exit[:time]}</td>
          <td>#{exit[:price]}</td>
          <td class="#{profit_class}">$#{profit.round(2)}</td>
        </tr>
          HTML
        end
        
        table_html += <<-HTML
      </tbody>
    </table>
        HTML
        
        table_html
      end
      
      def price_data_json
        data_points = @chart_data.price_data.map do |point|
          {
            x: point[:time],
            y: point[:close]
          }
        end
        
        # JSON文字列に変換する
        JSON.generate(data_points)
      end
      
      def equity_data_json
        data_points = @chart_data.equity_curve.map do |point|
          {
            x: point[:time],
            y: point[:balance]
          }
        end
        
        # JSON文字列に変換する
        JSON.generate(data_points)
      end
      
      def drawdown_data_json
        data_points = @chart_data.equity_curve.map do |point|
          {
            x: point[:time],
            y: point[:drawdown]
          }
        end
        
        # JSON文字列に変換する
        JSON.generate(data_points)
      end

      
      def generate_trade_points_datasets
        return "" if @chart_data.trade_points.empty?

        # エントリーポイント（買い）
        buy_entries = @chart_data.trade_points.select { |p| p[:action] == 'entry' && p[:type] == 'buy' }
        buy_entries_json = JSON.generate(buy_entries.map do |point|
          { x: point[:time], y: point[:price] }
        end)

        buy_entries_data = "{ label: 'エントリー(買)', data: #{buy_entries_json}, tradeData: #{JSON.generate(buy_entries)}, backgroundColor: 'rgba(0, 128, 0, 0.9)', borderColor: 'green', pointRadius: 8, pointStyle: 'triangle', showLine: false }"
        # エントリーポイント（売り）
        sell_entries = @chart_data.trade_points.select { |p| p[:action] == 'entry' && p[:type] == 'sell' }
        sell_entries_json = JSON.generate(sell_entries.map do |point|
          { x: point[:time], y: point[:price] }
        end)
        
        sell_entries_data = "{ label: 'エントリー(売)', data: #{sell_entries_json}, tradeData: #{JSON.generate(sell_entries)}, backgroundColor: 'red', borderColor: 'red', pointRadius: 6, pointStyle: 'triangle', showLine: false }"
        
        # 決済ポイント（買い）
        buy_exits = @chart_data.trade_points.select { |p| p[:action] == 'exit' && p[:type] == 'buy' }
        buy_exits_json = JSON.generate(buy_exits.map do |point|
          { x: point[:time], y: point[:price] }
        end)
        
        buy_exits_data = "{ label: '決済(買)', data: #{buy_exits_json}, tradeData: #{JSON.generate(buy_exits)}, backgroundColor: 'rgba(0, 128, 0, 0.5)', borderColor: 'green', pointRadius: 6, pointStyle: 'circle', showLine: false }"
        
        # 決済ポイント（売り）
        sell_exits = @chart_data.trade_points.select { |p| p[:action] == 'exit' && p[:type] == 'sell' }
        sell_exits_json = JSON.generate(sell_exits.map do |point|
          { x: point[:time], y: point[:price] }
        end)
        
        sell_exits_data = "{ label: '決済(売)', data: #{sell_exits_json}, tradeData: #{JSON.generate(sell_exits)}, backgroundColor: 'rgba(255, 0, 0, 0.5)', borderColor: 'red', pointRadius: 6, pointStyle: 'circle', showLine: false }"
        
        datasets = []
        datasets << buy_entries_data unless buy_entries.empty?
        datasets << sell_entries_data unless sell_entries.empty?
        datasets << buy_exits_data unless buy_exits.empty?
        datasets << sell_exits_data unless sell_exits.empty?
        
        datasets.join(",\n          ")
      end
    end
  end
end
