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
<html lang="ja">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>#{title}</title>
  <!-- Chart.js 本体 -->
  <script src="https://cdn.jsdelivr.net/npm/chart.js@4"></script>
  <!-- zoom プラグイン -->
  <script src="https://cdn.jsdelivr.net/npm/chartjs-plugin-zoom@2"></script>
  <script src="https://cdn.jsdelivr.net/npm/chartjs-adapter-date-fns"></script>
  <!-- jQuery（表の操作に使用） -->
  <script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
  <!-- DataTablesプラグイン -->
  <link rel="stylesheet" type="text/css" href="https://cdn.datatables.net/1.11.5/css/jquery.dataTables.css">
  <script type="text/javascript" charset="utf8" src="https://cdn.datatables.net/1.11.5/js/jquery.dataTables.js"></script>

  <script>
    Chart.register(window.ChartZoom);
  </script>

  <style>
    body {
      font-family: 'Segoe UI', 'メイリオ', sans-serif;
      margin: 20px;
      background-color: #f5f5f5;
      color: #333;
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
      border-bottom: 2px solid #eee;
      padding-bottom: 20px;
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
      transition: transform 0.2s;
    }
    .stat-box:hover {
      transform: translateY(-5px);
      box-shadow: 0 4px 8px rgba(0,0,0,0.15);
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
      white-space: nowrap;
    }
    th {
      background-color: #f2f2f2;
      position: sticky;
      top: 0;
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
    .balance-chart-container {
      height: 350px;
      margin-bottom: 30px;
    }
    .indicator-controls {
      margin-bottom: 20px;
      padding: 15px;
      background-color: #f8f9fa;
      border-radius: 6px;
    }
    .checkbox-group {
      display: flex;
      flex-wrap: wrap;
      gap: 15px;
    }
    .checkbox-group label {
      display: flex;
      align-items: center;
      cursor: pointer;
    }
    .checkbox-group input {
      margin-right: 5px;
    }
    .trade-details {
      margin-top: 20px;
      border: 1px solid #ddd;
      border-radius: 6px;
      overflow: hidden;
    }
    .tab-controls {
      display: flex;
      background-color: #f2f2f2;
      border-bottom: 1px solid #ddd;
    }
    .tab-button {
      padding: 10px 20px;
      background: none;
      border: none;
      cursor: pointer;
      font-weight: bold;
      color: #555;
    }
    .tab-button.active {
      background-color: white;
      color: #007bff;
      border-bottom: 2px solid #007bff;
    }
    .tab-content {
      display: none;
      padding: 15px;
    }
    .tab-content.active {
      display: block;
    }
    .trade-row {
      cursor: pointer;
    }
    .trade-row:hover {
      background-color: #e9f5ff !important;
    }
    .trade-details-panel {
      display: none;
      padding: 15px;
      background-color: #f9f9f9;
      border-top: 1px solid #ddd;
    }
    .trade-details-title {
      font-weight: bold;
      margin-bottom: 10px;
    }
    .trade-details-content {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(250px, 1fr));
      gap: 10px;
    }
    .trade-detail-item {
      display: flex;
      justify-content: space-between;
      padding: 5px 0;
      border-bottom: 1px dashed #eee;
    }
    .button-container {
      display: flex;
      gap: 10px;
      margin-bottom: 15px;
    }
    button {
      padding: 8px 15px;
      background-color: #007bff;
      color: white;
      border: none;
      border-radius: 4px;
      cursor: pointer;
      transition: background-color 0.2s;
    }
    button:hover {
      background-color: #0069d9;
    }
    .accordion {
      background-color: #f8f9fa;
      color: #444;
      cursor: pointer;
      padding: 18px;
      width: 100%;
      text-align: left;
      border: none;
      outline: none;
      transition: 0.4s;
      margin-bottom: 5px;
      border-radius: 4px;
      font-weight: bold;
    }
    .active-accordion, .accordion:hover {
      background-color: #e7f1ff;
    }
    .panel {
      padding: 0 18px;
      background-color: white;
      max-height: 0;
      overflow: hidden;
      transition: max-height 0.2s ease-out;
      border-radius: 0 0 4px 4px;
    }
    .accordion:after {
      content: '\\002B';
      color: #777;
      font-weight: bold;
      float: right;
      margin-left: 5px;
    }
    .active-accordion:after {
      content: "\\2212";
    }
    .dataTables_wrapper {
      padding: 10px;
      margin-bottom: 20px;
    }
    .dataTables_filter {
      margin-bottom: 10px;
    }
    .equity-info {
      margin-top: 10px;
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
      gap: 10px;
    }
    .equity-item {
      padding: 10px;
      background-color: #f8f9fa;
      border-radius: 4px;
    }
    .equity-label {
      font-weight: bold;
      color: #555;
    }
    .equity-value {
      margin-top: 5px;
      font-size: 18px;
    }
    .tooltip {
      position: relative;
      display: inline-block;
      border-bottom: 1px dotted #666;
      cursor: help;
    }
    .tooltip .tooltiptext {
      visibility: hidden;
      width: 200px;
      background-color: #555;
      color: #fff;
      text-align: center;
      border-radius: 6px;
      padding: 5px;
      position: absolute;
      z-index: 1;
      bottom: 125%;
      left: 50%;
      margin-left: -100px;
      opacity: 0;
      transition: opacity 0.3s;
    }
    .tooltip:hover .tooltiptext {
      visibility: visible;
      opacity: 1;
    }
    .section-title {
      font-size: 22px;
      font-weight: bold;
      margin: 30px 0 15px 0;
      padding-bottom: 10px;
      border-bottom: 2px solid #eee;
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

    <div class="section-title">資産推移</div>
    <div class="balance-chart-container">
      <canvas id="equityChart"></canvas>
    </div>

    <div class="equity-info">
      <div class="equity-item">
        <div class="equity-label">初期残高</div>
        <div class="equity-value">$#{format_number(@chart_data.results[:params][:Start_Sikin] || 0)}</div>
      </div>
      <div class="equity-item">
        <div class="equity-label">最終残高</div>
        <div class="equity-value">$#{format_number(calculate_final_balance)}</div>
      </div>
      <div class="equity-item">
        <div class="equity-label">総利益</div>
        <div class="equity-value positive">$#{format_number(@chart_data.results[:total_profit] || 0)}</div>
      </div>
      <div class="equity-item">
        <div class="equity-label">最大ドローダウン</div>
        <div class="equity-value negative">$#{format_number(@chart_data.results[:max_drawdown] || 0)}</div>
      </div>
    </div>

    <div class="section-title">価格チャート</div>
    <div class="indicator-controls">
      <h3>テクニカル指標</h3>
      <div class="checkbox-group">
        <label><input type="checkbox" id="showFastMA" checked> 短期MA(5)</label>
        <label><input type="checkbox" id="showSlowMA" checked> 長期MA(14)</label>
        <label><input type="checkbox" id="showMomentum"> モメンタム(20)</label>
      </div>
    </div>

    <div class="button-container">
      <button id="resetZoom">ズームをリセット</button>
      <button id="toggleTradeMarkers">取引マーカー表示切替</button>
    </div>

    <div class="chart-container">
      <canvas id="priceChart"></canvas>
    </div>

    <div class="section-title">取引履歴</div>
    <div id="tradesTableContainer">
      <table id="tradesTable" class="display" style="width:100%">
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
            <th>ポジション数</th>
            <th>エントリー残高</th>
            <th>決済後残高</th>
            <th>エントリー理由</th>
            <th>決済理由</th>
          </tr>
        </thead>
        <tbody>
          #{generate_detailed_trades_table_rows}
        </tbody>
        <tfoot>
          <tr>
            <th colspan="7" style="text-align:right">合計:</th>
            <th>$#{format_number(@chart_data.results[:total_profit] || 0)}</th>
            <th></th>
            <th></th>
          </tr>
        </tfoot>
      </table>
    </div>
  </div>

  <script>
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
          tension: 0.1,
          yAxisID: 'y'
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
      interaction: {
        intersect: false,
        mode: 'index'
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
        },
        tooltip: {
          callbacks: {
            label: function(context) {
              const label = context.dataset.label || '';
              if (label === '残高') {
                return `残高: $${context.parsed.y.toFixed(2)}`;
              } else if (label === 'ドローダウン') {
                return `ドローダウン: $${context.parsed.y.toFixed(2)}`;
              }
              return label;
            }
          }
        },
        zoom: {
          zoom: {
            wheel: { enabled: true, modifierKey: 'ctrl' },
            pinch: { enabled: true },
            mode: 'x',
            overScaleMode: 'y'
          },
          pan: {
            enabled: true,
            mode: 'x',
            modifierKey: 'shift'
          },
          limits: {
            x: { min: 'original', max: 'original' },
            y: { min: 'original', max: 'original' }
          }
        }
      }
    }
  });

  //価格チャートの設定
  const tradeDatasets = [];
  let showTradeMarkers = true;
  
  function updateTradeMarkers() {
    const datasets = priceChart.data.datasets;
    for (let i = 0; i < datasets.length; i++) {
      if (datasets[i].isTradeMarker) {
        datasets[i].hidden = !showTradeMarkers;
      }
    }
    priceChart.update();
  }
  
  document.getElementById('toggleTradeMarkers').addEventListener('click', function() {
    showTradeMarkers = !showTradeMarkers;
    updateTradeMarkers();
  });
  
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
        mode: 'index'
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
            color: 'rgba(200, 200, 200, 0.2)'
          }
        },
        y: {
          title: {
            display: true,
            text: '価格'
          },
          position: 'left',
          grid: {
            color: 'rgba(200, 200, 200, 0.2)'
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
          zoom: {
            wheel: { enabled: true, modifierKey: 'ctrl' },
            pinch: { enabled: true },
            mode: 'x',
            overScaleMode: 'y'
          },
          pan: {
            enabled: true,
            mode: 'x',
            modifierKey: 'shift'
          },
          limits: {
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
            usePointStyle: true
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

  document.getElementById('resetZoom').addEventListener('click', () => {
    priceChart.resetZoom();
    equityChart.resetZoom();
  });

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

  // データテーブルの初期化
  $(document).ready(function() {
    $('#tradesTable').DataTable({
      "language": {
        "url": "https://cdn.datatables.net/plug-ins/1.11.5/i18n/ja.json"
      },
      "order": [[0, "asc"]],
      "pageLength": 25,
      "lengthMenu": [[10, 25, 50, 100, -1], [10, 25, 50, 100, "全て"]],
      "columnDefs": [
        { "width": "80px", "targets": 0 },
        { 
          "targets": 7,
          "render": function(data, type, row) {
            if (type === 'display') {
              const profit = parseFloat(data.replace('$', ''));
              return profit >= 0 
                ? `<span class="positive">${data}</span>` 
                : `<span class="negative">${data}</span>`;
            }
            return data;
          }
        }
      ]
    });
    
    // 取引行クリック時のイベント
    $('#tradesTable tbody').on('click', 'tr', function() {
      const table = $('#tradesTable').DataTable();
      const data = table.row(this).data();
      
      if (data) {
        const tradeIndex = parseInt(data[0]) - 1;
        highlightTrade(tradeIndex);
      }
    });
  });
  
  // チャート上で取引を強調表示する関数
  function highlightTrade(tradeIndex) {
    // 価格チャート上で該当する取引のエントリーと決済ポイントを強調表示
    const pointStyle = {
      radius: 12,
      borderWidth: 3
    };
    
    // 一度すべてのポイントを元のサイズに戻す
    priceChart.data.datasets.forEach(dataset => {
      if (dataset.isTradeMarker) {
        dataset.pointRadius = dataset._originalRadius || 6;
        dataset.borderWidth = dataset._originalBorderWidth || 1;
      }
    });
    
    // クリックされた取引を強調表示
    const entryIndex = tradeIndex * 2;  // 取引の入口は偶数インデックス
    const exitIndex = tradeIndex * 2 + 1;  // 取引の出口は奇数インデックス
    
    let foundEntry = false;
    let foundExit = false;
    
    for (let i = 0; i < priceChart.data.datasets.length; i++) {
      const dataset = priceChart.data.datasets[i];
      if (!dataset.isTradeMarker) continue;
      
      // エントリーポイントの強調表示
      if (dataset.label.includes('エントリー') && dataset.data[entryIndex]) {
        dataset._originalRadius = dataset.pointRadius;
        dataset._originalBorderWidth = dataset.borderWidth;
        dataset.pointRadius = pointStyle.radius;
        dataset.borderWidth = pointStyle.borderWidth;
        foundEntry = true;
      }
      
      // 決済ポイントの強調表示
      if (dataset.label.includes('決済') && dataset.data[exitIndex]) {
        dataset._originalRadius = dataset.pointRadius;
        dataset._originalBorderWidth = dataset.borderWidth;
        dataset.pointRadius = pointStyle.radius;
        dataset.borderWidth = pointStyle.borderWidth;
        foundExit = true;
      }
      
      if (foundEntry && foundExit) break;
    }
    
    priceChart.update();
    
    // チャート上の該当ポイントが見えるようにスクロール
    if (foundEntry || foundExit) {
      const targetTime = foundEntry 
        ? priceChart.data.datasets.find(d => d.isTradeMarker && d.label.includes('エントリー')).data[entryIndex].x
        : priceChart.data.datasets.find(d => d.isTradeMarker && d.label.includes('決済')).data[exitIndex].x;
      
      // ズームレベルを調整して該当ポイント付近を表示
      const timeRange = priceChart.scales.x.max - priceChart.scales.x.min;
      const newMin = new Date(targetTime).getTime() - timeRange / 4;
      const newMax = new Date(targetTime).getTime() + timeRange / 4;
      
      priceChart.zoomScale('x', {min: newMin, max: newMax}, 'default');
    }
  }
  </script>
</body>
</html>
HTML

        html
      end
      
      private
      
      def format_number(number, decimals = 5)
        return "0.00" if number.nil?
        format("%.#{decimals}f", number)
      end

      # 通貨付き数値フォーマット関数を追加
      def format_currency(number, currency = "USD", decimals = 5)
        return "$0.00" if number.nil?
        
        symbol = currency == "USD" ? "$" : "¥"
        decimals = currency == "USD" ? decimals : 2  # JPYは小数点以下2桁
        
        "#{symbol}#{format_number(number, decimals)}"
      end

      def calculate_final_balance
        initial_balance = @chart_data.results[:params][:Start_Sikin] || 0
        total_profit = @chart_data.results[:total_profit] || 0
        
        initial_balance + total_profit
      end

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
        
        # プロフィットファクター
        if losing_trades > 0 && losing_trades > 0
          winning_sum = @chart_data.trade_points.select { |p| p[:action] == 'exit' && p[:profit] && p[:profit] > 0 }.sum { |p| p[:profit] }
          losing_sum = @chart_data.trade_points.select { |p| p[:action] == 'exit' && p[:profit] && p[:profit] <= 0 }.sum { |p| p[:profit] }.abs
          profit_factor = losing_sum > 0 ? (winning_sum / losing_sum).round(2) : 0
        else
          profit_factor = 0
        end
        
        # 期待値
        expected_payoff = total_trades > 0 ? (total_profit / total_trades).round(2) : 0
        
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
        <div class="stat-value #{total_profit >= 0 ? 'positive' : 'negative'}">¥#{format_number(total_profit)}</div>
      </div>
      <div class="stat-box">
        <div class="stat-title">最大ドローダウン</div>
        <div class="stat-value negative">¥#{format_number(max_drawdown)}</div>
      </div>
      <div class="stat-box">
        <div class="stat-title">プロフィットファクター</div>
        <div class="stat-value #{profit_factor >= 1 ? 'positive' : 'negative'}">#{profit_factor}</div>
      </div>
      <div class="stat-box">
        <div class="stat-title">期待値</div>
        <div class="stat-value #{expected_payoff >= 0 ? 'positive' : 'negative'}">$#{format_number(expected_payoff)}</div>
      </div>
        HTML
        
        stats_html
      end
      
      def generate_detailed_trades_table_rows
        return "" if @chart_data.trade_points.empty?
  # トレードポイントが空でないことをログ出力
  puts "トレードポイント数: #{@chart_data.trade_points.size}"

puts "=== トレード情報 ==="
@chart_data.trade_points.select { |p| p[:action] == 'exit' }.each_with_index do |point, idx|
  puts "#{idx+1}: profit=#{point[:profit]}, currency=#{point[:currency]}, display=#{point[:profit_display]}"
end

        # エントリーと決済をペアにする
        entry_points = @chart_data.trade_points.select { |p| p[:action] == 'entry' }
        exit_points = @chart_data.trade_points.select { |p| p[:action] == 'exit' }

  # デバッグ用に数を出力
  puts "エントリーポイント数: #{entry_points.size}, 決済ポイント数: #{exit_points.size}"

        # 取引ペアは少ないほうに合わせる
        trade_count = [entry_points.size, exit_points.size].min
  puts "処理する取引ペア数: #{trade_count}"

  rows_html = ""
        
        trade_count.times do |i|
          entry = entry_points[i]
          exit = exit_points[i]

    # エントリーまたは決済データがない場合はスキップ
    next if entry.nil? || exit.nil?

    # 通貨単位を取得（なければUSDをデフォルトに）
    currency = exit[:currency] || entry[:currency] || "JPY"

          profit = exit[:profit] || 0
          profit_class = profit > 0 ? 'positive' : (profit < 0 ? 'negative' : 'neutral')

    # 1. 通貨単位に応じた利益表示文字列を作成
    profit_display = if exit[:profit_display]
      # process_trade_pointsで既に作成された表示文字列があれば使用
      exit[:profit_display]
    else
      # なければここで作成
      currency == "JPY" ? 
        "¥#{format('%.2f', profit)}" : 
        "$#{format('%.5f', profit)}"
    end

          type_text = entry[:type] == 'buy' ? '買い' : '売り'
          entry_reason = entry[:reason] || '-'
          exit_reason = exit[:reason] || '-'
          
    # 2. 残高情報の通貨単位も考慮
    entry_balance_currency = entry[:balance_currency] || "JPY"  # 残高通貨はデフォルトでJPY
    exit_balance_currency = exit[:balance_currency] || "JPY"
    
    # 3. 通貨単位に応じた残高表示
    entry_balance_display = entry[:account_balance] ? 
      (entry_balance_currency == "USD" ? "$#{format_number(entry[:account_balance])}" : "¥#{format_number(entry[:account_balance], 2)}") : 
      "-"
    
    exit_balance_display = exit[:account_balance] ? 
      (exit_balance_currency == "USD" ? "$#{format_number(exit[:account_balance])}" : "¥#{format_number(exit[:account_balance], 2)}") : 
      "-"
    
    # ポジション数情報（あれば表示）
    positions_count = entry[:positions_count] || entry[:entry_positions_count] || 0
    
          
          rows_html += <<-HTML
            <tr class="trade-row">
              <td>#{i + 1}</td>
              <td>#{type_text}</td>
              <td>#{format('%.2f', entry[:lot].to_f)}</td>
              <td>#{entry[:time]}</td>
              <td>#{format_number(entry[:price])}</td>
              <td>#{exit[:time]}</td>
              <td>#{format_number(exit[:price])}</td>
              <td class="#{profit_class}">#{profit_display}</td>
              <td>#{positions_count}</td>
              <td>#{entry_balance_display}</td>
              <td>#{exit_balance_display}</td>
              <td>#{entry_reason}</td>
              <td>#{exit_reason}</td>
            </tr>
          HTML
        end
        
        rows_html
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

        buy_entries_data = "{ label: 'エントリー(買)', data: #{buy_entries_json}, tradeData: #{JSON.generate(buy_entries)}, backgroundColor: 'rgba(0, 128, 0, 0.9)', borderColor: 'green', pointRadius: 8, pointStyle: 'triangle', showLine: false, isTradeMarker: true, _originalRadius: 8 }"
        # エントリーポイント（売り）
        sell_entries = @chart_data.trade_points.select { |p| p[:action] == 'entry' && p[:type] == 'sell' }
        sell_entries_json = JSON.generate(sell_entries.map do |point|
          { x: point[:time], y: point[:price] }
        end)
        
        sell_entries_data = "{ label: 'エントリー(売)', data: #{sell_entries_json}, tradeData: #{JSON.generate(sell_entries)}, backgroundColor: 'red', borderColor: 'red', pointRadius: 6, pointStyle: 'triangle', showLine: false, isTradeMarker: true, _originalRadius: 6 }"
        
        # 決済ポイント（買い）
        buy_exits = @chart_data.trade_points.select { |p| p[:action] == 'exit' && p[:type] == 'buy' }
        buy_exits_json = JSON.generate(buy_exits.map do |point|
          { x: point[:time], y: point[:price] }
        end)
        
        buy_exits_data = "{ label: '決済(買)', data: #{buy_exits_json}, tradeData: #{JSON.generate(buy_exits)}, backgroundColor: 'rgba(0, 128, 0, 0.5)', borderColor: 'green', pointRadius: 6, pointStyle: 'circle', showLine: false, isTradeMarker: true, _originalRadius: 6 }"
        
        # 決済ポイント（売り）
        sell_exits = @chart_data.trade_points.select { |p| p[:action] == 'exit' && p[:type] == 'sell' }
        sell_exits_json = JSON.generate(sell_exits.map do |point|
          { x: point[:time], y: point[:price] }
        end)
        
        sell_exits_data = "{ label: '決済(売)', data: #{sell_exits_json}, tradeData: #{JSON.generate(sell_exits)}, backgroundColor: 'rgba(255, 0, 0, 0.5)', borderColor: 'red', pointRadius: 6, pointStyle: 'circle', showLine: false, isTradeMarker: true, _originalRadius: 6 }"
        
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