#include <stderror.mqh>
#include <stdlib.mqh>
//+------------------------------------------------------------------+
//|                                 Rakuten_GBPUSD_ZA701_Trevian.mq4 |
//|                                Copyright © 2021, WINSIDE co.,LTD |
//|                                            https://trevian.site/ |
//|                         Last Modify 2025/02/24 by Kenji Nakajima |
//+------------------------------------------------------------------+
#property copyright "Copyright © 2021, WINSIDE co.,LTD Kenji Nakajima"
#property link      "https://trevian.site"
#property version   "7.01"
#property strict

#property description "TREVIAN Licence Ver ZA701_Trevian 2025/02/24"

//
//--Document
//
// Trevian Rakuten GBPUSD
// GBPUSD
// LossCutPosition:5～6
// LossCutProfit:Input
// LosCutPlus:Input
//
// TrailingStop trailLength:Input
//
// 福利運用
//
// LossCut+LossCutPlus
//
// LossCut BugFix(limit_rate)
//
// 極利（Max Lot Calc）
// MinusLot
// MaxLotX
//

// 入力パラメータ宣言
//
double   Gap               = 4000.0;
double   Takeprofit        = 60.0;
double   Start_Lots        = 0.95;

double   Gap_down_Percent    = 0;    //--Gapを狭くするdown_Percent
double   Profit_down_Percent = 0;    //--Profitを狭くするdown_Percent

int      strategy_test     = 0;     //--本番

int      Start_Sikin       = 300;  //--資金

double   MinusLot          = 0.99;
double   MaxLotX           = 100;


//--Lot制限、Position制限
//
double   lot_seigen        = 100;
int      lot_pos_seigen    = 30;

//--Fukuri
//
double   fukuri            = 1;

double   limit_baisu       = 10;    //--Limit 倍数

double   keisu_x           = 9.9;  //--next_order_keisu係数計算の係数
double   keisu_pulus_pips  = 0.35;

int      position_x        = 1;     //--Gap,Profitを広げるPosition数から

double   profit_zz_total    = 0;


double   SpredKeisuu       = 10000;   //--通貨の小数点以下の調整


double GapProfit = Gap;

double next_order_keisu = ((GapProfit + Takeprofit) / Takeprofit)*keisu_x;


//--システム設定
//
int      MAGIC             = 8888;  //--Trevian
double   BaseLots          = 1.0;
int      EA_Emergency      = 0;
//
double   profit_rate       = Takeprofit / SpredKeisuu;


//--user 口座確認?
//
int      user_flag         = 0;     //--1:口座あり 0:無効
long     user_no           = 0;     //--user_no
int      EA_Stop           = 0;     //--EA 0:通常 1:Stop 2:Start

//--work variable
//
double   Lots              = BaseLots;
//
int      lot_FreeMargin    = 10000;
int      orders            = 0;
int      Buy_orders        = 0;
int      Sell_orders       = 0;
int      Limit_orders      = 0;
int      Limit_Buy_orders  = 0;
int      Limit_Sell_orders = 0;
int      total_orders      = 0;
double   limit_rate;

//
//--Server Timer
//
int      loop_cnt          = 0;
int      loop_cnt2         = 0;
int      server_timer      = 4000;      //--約60分

//
//--実処理
//
int      Order_jyotai      = 0;        //--0:first 1:rieki_serch
int      Order_MAGIC       = MAGIC;
int      First_Order       = 0;        //--1:Buy 2:Sell
int      Next_Order        = 0;        //--1:Buy 2:Sell
int      Next_No           = 0;        //--Order No
int      rieki_flag        = 0;
double   first_rate        = 0;
double   order_rate        = 0;
double   first_Lots        = 0;

int      pass_time_count   = 50;
int      syori_chu_flag    = 0;

//--逆に動いた時
//
int      total_nariyuki    = 0;
int      nariyuki_flag     = 0;
double   next_order_lots   = 0;
double   next_order_rate   = 0;
int      next_icount       = 0;

int      next_Finish_Flag  = 0;
double   All_lots          = 0;
//
int      All_position      = 0;
//
int      Plus_Flag         = 0;
int      NormalLoopCount   = 0;

double   buy_rate          = 0;
double   sell_rate         = 0;

//
int      close_flag        = 0;
int      all_delete_flag   = 0;

int      Ticket_no         = 0;
int      ticket_read_flag  = 0;

int      EA_Stop_Save      = 0;

//--LosCutParameter
//
int      LosCutPosition    = 15;
//input double   LosCutProfit      = -20000; //--円

double   LosCutProfit      = -900;   //--$LossCut

double   LosCutPlus        = -40;    //--$LossCutPlus

//--TrailingStop Point
//
int      trailLength       = 99;
int      TrailingStop_Flag = 0;
int      LastTicket        = 0;
double   LastLots          = 0;


   
//+------------------------------------------------------------------+
//| OnInit(初期化)イベント 
//+------------------------------------------------------------------+
void OnInit() {

   //--Action Data Get
   //
   if(strategy_test == 0) GetTradingData();
   
   int  server_time = Hour();
   printf("サーバー時間は%d"+IntegerToString(server_time));
   
   int youbi = TimeDayOfWeek(TimeLocal());
   int jikan = TimeHour(TimeLocal());
   int fun = TimeMinute(TimeLocal());
   printf("youbi=%d,jikan=%d,fun=%d",youbi,jikan,fun);
   
   GapProfit = Gap;
   next_order_keisu = ((GapProfit + Takeprofit) / Takeprofit)*keisu_x;
   
   //printf("GapProfit=%f,Takeprofit=%f,keisu_x=%f,next_order_keisu=%f",GapProfit,Takeprofit,keisu_x,next_order_keisu);
   
   
   Print("ストップレベル(0.1pips) =",MarketInfo(Symbol(),MODE_STOPLEVEL));
   Print("スプレッド(0.1pips)     =",MarketInfo(Symbol(),MODE_SPREAD));
   
   if(strategy_test == 0 && user_flag == 0) {
      string message = "口座" + IntegerToString(AccountNumber()) + "がユーザー情報に存在しません、EAをコピーする事は違法で許されません！";
   
      MessageBox(message,"エラー",MB_ICONEXCLAMATION);
   } else {
      //StopOrderDelete();
   }
   

}
//+------------------------------------------------------------------+
//| 保有中のポジションを計算                                        |
//+------------------------------------------------------------------+
int CalculateCurrentOrders( void ) {

    Limit_Buy_orders = Limit_Sell_orders = Buy_orders = Sell_orders = 0;
    // 現在アカウントで保有しているポジション数分ループ処理を行う
    for (int icount = 0 ; icount < OrdersTotal() ; icount++) {

        // 注文プールからエントリー中の注文を選択する
        if( OrderSelect(icount,SELECT_BY_POS,MODE_TRADES) == false) {
            break; // 注文選択に失敗したらループ処理終了
        }

        if( OrderSymbol() == Symbol() && OrderMagicNumber() >= MAGIC) {
            if(OrderType()==OP_BUY) {
                Buy_orders++;
            }
            if(OrderType()==OP_BUYSTOP) {
                Limit_Buy_orders++;
            }
            if(OrderType()==OP_SELL) {
                Sell_orders++;
            }
            if(OrderType()==OP_SELLSTOP) {
                Limit_Sell_orders++;
            }
        }
    }
    //
    Limit_orders = Limit_Buy_orders + Limit_Sell_orders;
    orders = Buy_orders + Sell_orders;
    
    total_orders = Limit_orders + orders;
    
    return (total_orders);

}
//+------------------------------------------------------------------+
//| GetTradingData　システム情報をGet
//+------------------------------------------------------------------+
void GetTradingData() {
   
   int WebR;
   string URL = "https://trevian.site/get_Rakuten_trevian_V701.php";
   int timeout = 5000;
   string cookie = NULL,headers; 
   char post[],ReceivedData[];
   
   string str= "";
   str = "&close_flag=" + IntegerToString(close_flag) + "&kouza_no=" + IntegerToString(AccountNumber());
   str += "&zandaka=" + DoubleToString(AccountBalance());
   str += "&position=" + IntegerToString(orders);
   str += "&profit=" + DoubleToString(AccountProfit());
   
   
   str += "&";
   
   printf("str=%s",str);
   
   StringToCharArray( str, post );
   
   
   WebR = WebRequest( "POST", URL, cookie, NULL, timeout, post, 0, ReceivedData, headers );
   if(!WebR) Print("Web request failed");   
   
   if(WebR == -1) {// エラーチェック
        Print("WebRequesエラー。 エラーコード  =",GetLastError());
   }
   
   string TradingData = CharArrayToString(ReceivedData);
   
   int cnt = StringBufferLen(TradingData);
   
   string param = "";
   
   //
   user_flag = 0;
   EA_Stop_Save = EA_Stop;
   //
   for(int i=0; i<cnt; i++) {
      if(StringSubstr(TradingData , i, 1) == "&") {
         int pcnt = StringBufferLen(param);

         if(StringSubstr(param , 0, 4) == "Gap=") {
            Gap = StringToDouble(StringSubstr(param , 4, pcnt-4));
            user_flag = 1;
         } else
         if(StringSubstr(param , 0, 7) == "Profit=") {
            Takeprofit = StringToDouble(StringSubstr(param , 7, pcnt-7));
            user_flag = 1;
         } else
         if(StringSubstr(param , 0, 5) == "lots=") {
            Start_Lots = StringToDouble(StringSubstr(param , 5, pcnt-5));
            user_flag = 1;
         } else
         if(StringSubstr(param , 0, 8) == "GapDown=") {
            Gap_down_Percent = StringToDouble(StringSubstr(param , 8, pcnt-8));
            user_flag = 1;
         } else
         if(StringSubstr(param , 0, 11) == "ProfitDown=") {
            Profit_down_Percent = StringToDouble(StringSubstr(param , 11, pcnt-11));
            user_flag = 1;
         } else
         if(StringSubstr(param , 0, 8) == "keisu_x=") {
            keisu_x = StringToDouble(StringSubstr(param , 8, pcnt-8));
            user_flag = 1;
         } else
         if(StringSubstr(param , 0, 17) == "keisu_pulus_pips=") {
            keisu_pulus_pips = StringToDouble(StringSubstr(param , 17, pcnt-17));
            user_flag = 1;
         } else
         if(StringSubstr(param , 0, 11) == "position_x=") {
            position_x = (int)StringToDouble(StringSubstr(param , 11, pcnt-11));
            user_flag = 1;
         } else
         if(StringSubstr(param , 0, 15) == "LosCutPosition=") {
            LosCutPosition = (int)StringToDouble(StringSubstr(param , 15, pcnt-15));
            user_flag = 1;
         } else
         if(StringSubstr(param , 0, 13) == "LosCutProfit=") {
            LosCutProfit = StringToDouble(StringSubstr(param , 13, pcnt-13));
            user_flag = 1;
         } else
         if(StringSubstr(param , 0, 11) == "LosCutPlus=") {
            LosCutPlus = StringToDouble(StringSubstr(param , 11, pcnt-11));
            user_flag = 1;
         } else
         if(StringSubstr(param , 0, 8) == "MaxLotX=") {
            MaxLotX = StringToDouble(StringSubstr(param , 8, pcnt-8));
            user_flag = 1;
         } else
         if(StringSubstr(param , 0, 9) == "MinusLot=") {
            MinusLot = StringToDouble(StringSubstr(param , 9, pcnt-9));
            user_flag = 1;
         } else
         if(StringSubstr(param , 0, 12) == "trailLength=") {
            trailLength = (int)StringToDouble(StringSubstr(param , 12, pcnt-12));
            user_flag = 1;
         } else
         if(StringSubstr(param , 0, 12) == "Start_Sikin=") {
            Start_Sikin = (int)StringToDouble(StringSubstr(param , 12, pcnt-12));
            user_flag = 1;
         } else
         
         
         if(StringSubstr(param , 0, 8) == "ea_stop=") {
            EA_Stop = (int)StringToDouble(StringSubstr(param , 8, pcnt-8));
            user_flag = 1;
         }
         

         
         param = "";
      } else {
         param = param + StringSubstr(TradingData , i, 1);
      }
   }
   //
   //printf("Gap=%f,Takeprofit=%f,Start_Lots=%f,Gap_down_Percent=%f,Profit_down_Percent=%f",Gap,Takeprofit,Start_Lots,Gap_down_Percent,Profit_down_Percent);
   //printf("keisu_x=%f,keisu_pulus_pips=%f,position_x=%d",keisu_x,keisu_pulus_pips,position_x);
   //printf("LosCutPosition=%d,LosCutProfit=%f,LosCutPlus=%f",LosCutPosition,LosCutProfit,LosCutPlus);
   //printf("MaxLotX=%f,MinusLot=%f,Start_Sikin=%d,trailLength=%d",MaxLotX,MinusLot,Start_Sikin,trailLength);

}
//+------------------------------------------------------------------+
//| OnDeinit(アンロード)イベント
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    // 処理無し
}
//+--------------------------------------------------------------------------------------------------------------+
//| OnTick(tick受信)イベント
//+--------------------------------------------------------------------------------------------------------------+
void OnTick() {


   if(strategy_test == 0 && user_flag == 0) return;
   
   if(syori_chu_flag == 1) return;
   
   if(TrailingStop_Flag == 1 && OrdersTotal() == 1) {
      TrailingStop();
      return;
   }
   
   int OrderPosition = 0;
   for (int icount = 0 ; icount < OrdersTotal() ; icount++) {
      if( OrderSelect(icount,SELECT_BY_POS,MODE_TRADES) == false) {
         break;
      }
      if( OrderSymbol() == Symbol() && OrderMagicNumber() == MAGIC) OrderPosition++;
   }
   
   if(all_delete_flag == 1) {
      int ordersTotalx = OrderPosition;
      printf("all_delete_flag=%d,ordersTotalx=%d",all_delete_flag,ordersTotalx);
      if( ordersTotalx > 0) {
         AllDelete();
         return;
      } else {
         all_delete_flag = 0;
         printf("-------------all_delete_flag=%d",all_delete_flag);
      }
   }
   
   if(OrderPosition > 0) ProfitCheck();
   
   
   //
   //--サーバーから最新の設定値をread
   //
   int loop_counter_limit = server_timer;    //--大統領選挙の為、頻繁にやり取りする為(40)通常は200～2000
   //
   if(strategy_test == 0) {
      if(loop_cnt > loop_counter_limit) {
         loop_cnt = 0;
         GetTradingData();
         //
         GapProfit = Gap;
         next_order_keisu = ((GapProfit + Takeprofit) / Takeprofit)*keisu_x;
      }
      loop_cnt++;
   }
   
   
   int youbi = TimeDayOfWeek(TimeLocal());
   int jikan = TimeHour(TimeLocal());
   int fun = TimeMinute(TimeLocal());
   //
   if(strategy_test == 0) {
      //
      //--EA Stop Or Start
      //
      if(EA_Stop == 1) {
         if(close_flag == 0) close_flag = 1;
      } else
      if(EA_Stop == 2) {
         if(close_flag == 1)close_flag = 0;
         EA_Stop = 0;
      } else
      //
      //--曜日コントロール
      //
      if(OrderPosition > 0) {
         //
         //--金曜日の13時よりは手仕舞いする
         //
         if(close_flag == 0) {
            if(youbi == 5) {
               if(jikan >= 20) close_flag = 1;
            } else
            if(youbi == 6) {
               close_flag = 1;
            }
         }
      } else {
         //
         //--手仕舞い状態で月曜日の場合は１１時以降なら取引する
         //
         if(youbi == 1) {
            if(jikan >= 10) close_flag = 0;
            else
            if(close_flag == 0) close_flag = 1;
         } else 
         if(youbi > 1 && youbi < 5 ) {
            if(close_flag == 1)close_flag = 0;
         }
      }
      //
      if(EA_Stop_Save != EA_Stop) {
         //SetCloseFlag();
         EA_Stop_Save = EA_Stop;
      }
   }
   
   
      //
      //--OnTick Job Start
      //
      
      fukuri = floor(AccountBalance() / Start_Sikin);
      if(fukuri < 1) fukuri = 1;
      
      //
      //--Max Lot Calc
      //
      
      //Lots = Start_Lots * fukuri;
      
   
      // 現在保有中のポジション数をチェック
      if(CalculateCurrentOrders() > 0) {
         // ポジション保有している場合
         if(orders > 0 && TrailingStop_Flag == 0) NextJob();
         
      } else 
      if(TrailingStop_Flag == 1 && OrdersTotal() == 0) {
         TrailingStop_Flag = 0;
         AllDelete();
      } else{
         // ポジション保有していない場合
         if(all_delete_flag == 0 && TrailingStop_Flag == 0 && close_flag == 0) {
            Lots = GetKyokuri();
            FirstJob();  
         }  
      }

}
//+------------------------------------------------------------------+
//| 極利 その資金でのマックスLOT計算                                  |
//+------------------------------------------------------------------+
double GetKyokuri() {

    // 動的に最大ロットを計算
    double optimalStartLot = CalculateOptimalLot(Gap, Takeprofit, MaxLotX, LosCutPosition);
    
    if(optimalStartLot < 0.01) optimalStartLot = 0.01;
    else
    if(optimalStartLot > 0.05) optimalStartLot -= MinusLot;
    
    return optimalStartLot;
}
// ロット計算ロジック
double CalculateOptimalLot(double gap, double profit, double maxLot, int positions) {
    double startLot = 0.01;
    double lotCoefficient = ((gap + profit) / profit)*1.3;
    double lotArray[8]; // 配列のサイズを事前に定義
    double totalLots = 0;
    double syokokin_lot = 0;
    double bestStartLot = startLot;
    double LossCutProfit = LosCutProfit + (LosCutPlus * (fukuri - 1));
    double sikin = AccountBalance() + LossCutProfit;
    double yojyou_syokokin = 0;
    double hituyou_syokokin = 0;
    
    //Print("lotCoefficient: ", lotCoefficient);
    
    double marginRequiredPerLot = MarketInfo("GBPUSD", MODE_MARGINREQUIRED);
    if (marginRequiredPerLot <= 0) {
        marginRequiredPerLot = 100000 / 25; // デフォルト計算
    }
    //Print("marginRequiredPerLot: ", marginRequiredPerLot);

    // 最適なスタートロットを探索
    for (double testStartLot = startLot; testStartLot <= maxLot; testStartLot += 0.01) {
        totalLots = 0;
        syokokin_lot = 0;

        // 初期ポジションのロットを設定
        lotArray[0] = testStartLot;

        // ポジションごとのロット計算
        int MaxLotFlag = 0;
        for (int i = 1; i < positions; i++) {
            lotArray[i] = MathCeil((lotArray[i - 1] * lotCoefficient + 0.03) * 100) / 100;
            
            //Print("Lots: ", lotArray[i]);
            
            if(positions == 2 || positions == 4 || positions == 6 || positions == 8) {
               if (i % 2 == 1) { // ポジション2, 4, 6のロットを合計
                  totalLots += lotArray[i];
               }
               if (i % 2 == 0) { // ポジション1, 3, 5のロットを合計
                  syokokin_lot += lotArray[i];
               }
            } else
            if(positions == 3 || positions == 5 || positions == 7) {
               if (i % 2 == 1) { // ポジション1, 3, 5のロットを合計
                  syokokin_lot += lotArray[i];
                  
               }
               if (i % 2 == 0) { // ポジション2, 4のロットを合計
                  totalLots += lotArray[i];
               }
            }
            if(totalLots >= maxLot || syokokin_lot >= maxLot) {
               MaxLotFlag = 1;
               break;
            }
        }
        
        yojyou_syokokin = sikin - (syokokin_lot * marginRequiredPerLot);
        hituyou_syokokin = totalLots * marginRequiredPerLot;

        //Print("Ask: ", Ask,"Bid: ", Bid);
        //Print("yojyou_syokokin: ", yojyou_syokokin,"hituyou_syokokin: ", hituyou_syokokin);
        // マックスロットを超えない場合、最適なスタートロットを更新
        if(MaxLotFlag == 1) {
            break;
        } else
        if (yojyou_syokokin >= hituyou_syokokin) {
            bestStartLot = testStartLot;
        } else {
            //Print("totalLots: ", totalLots);
            //Print("syokokin_lot: ", syokokin_lot);
            break; // マックスロットを超えたら探索終了
        }
    }

    return bestStartLot;
}
//+------------------------------------------------------------------+
//| オーダー処理                                  |
//+------------------------------------------------------------------+
void FirstJob() {
   
   syori_chu_flag = 1;
   //
   profit_rate    = Takeprofit / SpredKeisuu;
   //
   double Ask2 = Ask;
   double Bid2 = Bid;
   
   int trend_hantei = 3;
   
   int buy_flag   = 0;
   int sell_flag  = 0;
   int buy_flag1  = 0;
   int sell_flag1 = 0;
   int buy_flag2  = 0;
   int sell_flag2 = 0;
   int buy_flag3  = 0;
   int sell_flag3 = 0;
   
   
   //--PerfectOrder
   //
   if(trend_hantei == 0 || trend_hantei == 1) {
      //
      //--EMA トレンドの判定
      //
      double EMA1 = iMA(NULL,0,7,0,MODE_EMA,PRICE_CLOSE,1); 
      double EMA2 = iMA(NULL,0,50,0,MODE_EMA,PRICE_CLOSE,1);
      double EMA3 = iMA(NULL,0,150,0,MODE_EMA,PRICE_CLOSE,1);
   
      
      // 上昇トレンドの場合
      if(EMA1 > EMA2 && EMA2 > EMA3 && Close[1] > EMA1){
         buy_flag1 = 1;
         //printf("EMA1=%f EMA2=%f EMA3=%f buy_flag=%d Ask2=%f",EMA1,EMA2,EMA3,buy_flag,Ask2);
      } else
      // 下降トレンドの場合
      if(EMA1 < EMA2 && EMA2 < EMA3 && Close[1] < EMA1){
         sell_flag1 = 1;
         //printf("EMA1=%f EMA2=%f EMA3=%f sell_flag=%d Bid2=%f",EMA1,EMA2,EMA3,sell_flag,Bid2);
      }
   }
   
   //--Momentum
   //
   if(trend_hantei == 0 || trend_hantei == 2) {
      //
      //--iMomentum トレンドの判定
      //
      int MomPeriod = 20;
      double mom1 = iMomentum(_Symbol, 0, MomPeriod, PRICE_CLOSE, 1);
      if(mom1 > 100) {
         buy_flag2 = 1;
      } else
      if(mom1 < 100) {
         sell_flag2 = 1;
      }
   }
   
   //--Moving Average
   //
   if(trend_hantei == 0 || trend_hantei == 3) {
      //int FastMAPeriod = 20;
      //int SlowMAPeriod = 50;
      
      int FastMAPeriod = 5;
      int SlowMAPeriod = 14;
      
      
      double FastMA1 = iMA(_Symbol, 0, FastMAPeriod, 0, MODE_SMA, PRICE_CLOSE, 1); 
      double FastMA2 = iMA(_Symbol, 0, FastMAPeriod, 0, MODE_SMA, PRICE_CLOSE, 2); 
      double SlowMA1 = iMA(_Symbol, 0, SlowMAPeriod, 0, MODE_SMA, PRICE_CLOSE, 1); 
      double SlowMA2 = iMA(_Symbol, 0, SlowMAPeriod, 0, MODE_SMA, PRICE_CLOSE, 2);

      
      if( FastMA2 > SlowMA2 && FastMA1 > SlowMA1) {
         buy_flag3 = 1;
      } else {
         sell_flag3 = 1;
      }
      /*
      if( FastMA2 < SlowMA2 && FastMA1 < SlowMA1) {
         sell_flag3 = 1;
      }
      */

   }
   if(trend_hantei == 0) {
      if(buy_flag1  == 1 && buy_flag2  == 1 && buy_flag3  == 1) buy_flag  = 1;
      if(sell_flag1 == 1 && sell_flag2 == 1 && sell_flag3 == 1) sell_flag = 1;
   } else
   if(trend_hantei == 1) {
      buy_flag  = buy_flag1;
      sell_flag = sell_flag1;
   } else
   if(trend_hantei == 2) {
      buy_flag  = buy_flag2;
      sell_flag = sell_flag2;
   } else
   if(trend_hantei == 3) {
      buy_flag  = buy_flag3;
      sell_flag = sell_flag3;
   }
   
   printf("buy_flag=%d,sell_flag=%d",buy_flag,sell_flag);
   
   if(buy_flag == 1 || sell_flag == 1) {
      //
      
      buy_rate  = Ask2;
      sell_rate = Bid2;
      
     
      
      //
      //-----------------------------------------------------BUYSTOP オーダーを出す。
      //
      if(buy_flag == 1) {
      
         //limit_rate = buy_rate + ( Takeprofit * Point() * take_profit_keisu)*2;
         
         //limit_rate = buy_rate + (Takeprofit/SpredKeisuu)*20;
         //limit_rate = NormalizeDouble(limit_rate,2);
         double buy_Lots = Lots;
         buy_Lots = NormalizeDouble(buy_Lots,2);
         //
         if(buy_Lots > 0) {
                  
            
                  
            int res = OrderSend(
                       Symbol(),      // 現在の通貨ペア
                       OP_BUY,    // ロングエントリー(指値)
                       buy_Lots,      // ロット設定
                       buy_rate,      // 
                       3,             // スリップページ
                       0,             // ストップロス設定：無し
                       0,    // リミット設定：無し
                       "LONG",        // コメント
                       MAGIC,         // マジックナンバー
                       0,             // 有効期限：無し
                       clrBlue);      // チャート上の注文矢印の色
            //
            if(res != -1) {
               //
               sell_rate      = buy_rate - (GapProfit/SpredKeisuu);
               //
               Next_Order = 2;
               next_icount = 0;
               NextOrder();
               //
               printf("OP_BUY res=%d buy_rate=%f buy_Lots=%f Ask=%f limit_rate=%f",res,buy_rate,buy_Lots,Ask2,limit_rate);
            }
         }
      } else
      
      //
      //-----------------------------------------------------SELLSTOP オーダーを出す。
      //
      if(sell_flag == 1) {
         
         //limit_rate = sell_rate - ( Takeprofit * Point() * take_profit_keisu)*2;
         
         //limit_rate = sell_rate - (Takeprofit/SpredKeisuu)*20;
         //limit_rate = NormalizeDouble(limit_rate,2);
         double sell_Lots = Lots;
         sell_Lots = NormalizeDouble(sell_Lots,2);
         //
         if(sell_Lots > 0) {
               
            
                  
            int res = OrderSend(
                       Symbol(),      // 現在の通貨ペア
                       OP_SELL,   // ロングエントリー(指値)
                       sell_Lots,     // ロット設定
                       sell_rate,     // 
                       3,             // スリップページ
                       0,             // ストップロス設定：無し
                       0,    // リミット設定：無し
                       "SHORT",       // コメント
                       MAGIC,         // マジックナンバー
                       0,             // 有効期限：無し
                       clrRed);       // チャート上の注文矢印の色
            //
            if(res != -1) {
               //
               buy_rate       = sell_rate + (GapProfit/SpredKeisuu);
               //
               Next_Order = 1;
               next_icount = 0;
               NextOrder();
               //
               printf("OP_SELL res=%d sell_rate=%f sell_Lots=%f Bid=%f Ask=%f limit_rate=%f",res,sell_rate,sell_Lots,Bid2,Ask2,limit_rate);
            }   
         }
      }
   }
   Plus_Flag         = 0;
   syori_chu_flag    = 0;
}
//+------------------------------------------------------------------+
//| Next処理                                  |
//+------------------------------------------------------------------+
void NextJob() {
   
   syori_chu_flag    = 1;
   //
   double Ask2 = Ask;
   double Bid2 = Bid;
   
   //
   //--First Order Get
   //
   First_Order = 0;
   first_rate = 0;
   for (int icount = 0 ; icount < OrdersTotal() ; icount++) {
      if( OrderSelect(icount,SELECT_BY_POS,MODE_TRADES) == false) {
         break; // 注文選択に失敗したらループ処理終了
      }

      if( OrderSymbol() == Symbol() && OrderMagicNumber() == MAGIC) {
         if(OrderType()==OP_BUY) {
            First_Order    = 1;
            first_rate     = OrderOpenPrice();
            first_Lots     = OrderLots();
            buy_rate       = first_rate;
            sell_rate      = buy_rate - (GapProfit/SpredKeisuu);
         } else
         if(OrderType()==OP_SELL) {
            First_Order    = 2;
            first_rate     = OrderOpenPrice();
            first_Lots     = OrderLots();
            sell_rate      = first_rate;
            buy_rate       = sell_rate + (GapProfit/SpredKeisuu);
         }
         break;
      }
   }
   

   //
   //--総LOT計算
   //
   All_lots = 0;
   All_position = OrdersTotal();
   for (int icount = 0 ; icount < OrdersTotal() ; icount++) {
      if( OrderSelect(icount,SELECT_BY_POS,MODE_TRADES) == false) {
         break; // 注文選択に失敗したらループ処理終了
      }
      if( OrderSymbol() == Symbol() && OrderMagicNumber() >= MAGIC) {
         if(OrderType()==OP_BUY) {
            buy_rate = OrderOpenPrice();
         } else
         if(OrderType()==OP_SELL) {
            sell_rate = OrderOpenPrice();
         } 
         All_lots += OrderLots();
      }
   }
   
   
   //
   //--Next約定Check
   //
   ProfitCheck();
   
   
   
   //
   //--反転Check
   //
   if(First_Order >= 0 && OrdersTotal() < LosCutPosition) {
   //if(First_Order >= 0) {
   //if(First_Order >= 999) {
      //
      //--LimitOrderが約定
      //
      if(Limit_orders == 0) {
         nariyuki_flag = 0;
         int icount = orders -1;
         next_icount = icount;
         if( OrderSelect(icount,SELECT_BY_POS,MODE_TRADES) == true) {
            if( OrderSymbol() == Symbol() && OrderMagicNumber() >= MAGIC) {
               next_order_lots = OrderLots();
               if(OrderType()==OP_BUY) {
                  
                  
                  Next_Order = 2;
                  NextOrder(); 
                  
                  printf("Next_Order = 2");
                  
               } else
               if(OrderType()==OP_SELL) {
                  
                  
                  Next_Order = 1;
                  NextOrder(); 
                  
                  printf("Next_Order = 1");
                  
               }
            }
         }

         
      }
   }
   syori_chu_flag    = 0;
}
//+------------------------------------------------------------------+
//| Profit Rieki 判定                                  |
//+------------------------------------------------------------------+
void ProfitCheck() {
   //
   double profit_pips = Takeprofit;
   int    icount_x = orders -1;
   
   int MaxPos = 0;
   double TotalProfit = 0;
   int MaxPosition = 0;
   
   for (int icount = 0 ; icount < OrdersTotal() ; icount++) {
      if( OrderSelect(icount,SELECT_BY_POS,MODE_TRADES) == false) {
         
      } else
      if( OrderSymbol() == Symbol() && OrderMagicNumber() >= MAGIC) {
      
         if(OrderType()==OP_BUY) {
            MaxPos = icount;
            MaxPosition++;
            TotalProfit += OrderProfit();
         } else
         if(OrderType()==OP_SELL) {
            MaxPos = icount;
            MaxPosition++;
            TotalProfit += OrderProfit();
         }
      }
   }
   
   
   double LossCutProfit = LosCutProfit + (LosCutPlus * (fukuri - 1));
   
   //--LossCut 2023-06-03
   //
   //
   int LosCutFlag = 0;
   if(MaxPosition >= LosCutPosition) {
      if(TotalProfit < LossCutProfit) {
         AllDelete();
         LosCutFlag = 1;
      }
   }
   
   if(OrdersTotal() > 0 && LosCutFlag != 1) {
      if(icount_x > position_x) {
   
         profit_zz_total = (icount_x - position_x) * Profit_down_Percent;
         profit_pips = Takeprofit * (1-(profit_zz_total / 100));
      
      }
      //
      for (int icount = MaxPos; icount < OrdersTotal(); icount++) {
         if( OrderSelect(icount,SELECT_BY_POS,MODE_TRADES) == false) {
         
         } else
         if( OrderSymbol() == Symbol() && OrderMagicNumber() >= MAGIC) {
      
            if(OrderType()==OP_BUY) {
               order_rate = OrderOpenPrice();
               double rieki = (Bid - order_rate)*SpredKeisuu;
            
               //printf("rieki=%f",rieki);
            
               if(rieki >= profit_pips) {
                  TrailingStop_Control();
                  break;
               }
            } else
            if(OrderType()==OP_SELL) {
               order_rate = OrderOpenPrice();
               double rieki = (order_rate - Ask)*SpredKeisuu;
            
               //printf("rieki=%f",rieki);
            
               if(rieki >= profit_pips) {
                  TrailingStop_Control();
                  break;
               }
            }
         }
      }
   }
}
//+------------------------------------------------------------------+
//| NextOrder処理                                  |
//+------------------------------------------------------------------+
void NextOrder() {
   if(Next_Order == 0) {
      if(First_Order == 1) Next_Order = 2;
      else                 Next_Order = 1;
   }

   //
   //--Buy Order
   //
   if(Next_Order == 1) {
      //limit_rate = buy_rate + ( Takeprofit * Point() * take_profit_keisu)*2;
      
      //limit_rate = buy_rate + (Takeprofit/SpredKeisuu)*20;
      //limit_rate = NormalizeDouble(limit_rate,2);
      double buy_Lots = Lots*2;
      
      
      if(next_icount == 0) {
         buy_Lots = Lots*next_order_keisu+keisu_pulus_pips;
         profit_zz_total = 0;
      } else {
         buy_Lots = next_order_lots*next_order_keisu;
         if(next_icount >= position_x) {
            
            //--2021-09-04
            //
            profit_zz_total = (next_icount - position_x) * Profit_down_Percent;
            
            double rate_gap = buy_rate - sell_rate;
            double keisu_rate = (1-(Gap_down_Percent/100.0));
            
            buy_Lots *= (1+(Profit_down_Percent/100.0));
            buy_Lots += (keisu_pulus_pips*next_icount);
            
            double buy_ratex = sell_rate + ((buy_rate - sell_rate)*(1-(Gap_down_Percent/100.0)));
            
            printf("BUY next_icount=%d,position_x=%d,profit_zz_total=%f",next_icount,position_x,profit_zz_total);
            buy_rate = buy_ratex;
         }
      }
      
      //if(OrdersTotal() == LosCutPosition) buy_Lots = Lots;
      
      //buy_Lots = int(buy_Lots);
      
      buy_Lots = NormalizeDouble(buy_Lots,2);
      buy_rate = NormalizeDouble(buy_rate,5);
      
      next_Finish_Flag  = 0;
      
      All_lots += buy_Lots;
      if(All_lots >= lot_seigen)      next_Finish_Flag = 1;
      if(All_position >= lot_pos_seigen)  next_Finish_Flag = 1;
      
      if(next_Finish_Flag == 0) {
              
         bool res = OrderSend(
                    Symbol(),      // 現在の通貨ペア
                    OP_BUYSTOP,    // ロングエントリー(指値)
                    buy_Lots,      // ロット設定
                    buy_rate,      // 
                    3,             // スリップページ
                    0,             // ストップロス設定：無し
                    0,    // リミット設定：無し
                    "LONG",        // コメント
                    Order_MAGIC,   // マジックナンバー
                    0,             // 有効期限：無し
                    clrBlue);      // チャート上の注文矢印の色
         //
         int  res_Error = GetLastError();
         printf("NEXT OP_BUYSTOP buy_rate=%f buy_Lots=%f res_Error=%d",Ask,buy_Lots,res_Error);
      }
   } else
      
   //
   //--Sell Order
   //
   if(Next_Order == 2) {
      //limit_rate = sell_rate - ( Takeprofit * Point() * take_profit_keisu)*2;
      
      //limit_rate = sell_rate - (Takeprofit/SpredKeisuu)*20;
      //limit_rate = NormalizeDouble(limit_rate,2);
      double sell_Lots = Lots*2;
      
      if(next_icount == 0) {
         sell_Lots = Lots*next_order_keisu+keisu_pulus_pips;
         profit_zz_total = 0;
      } else {
         sell_Lots = next_order_lots*next_order_keisu;
         if(next_icount >= position_x) {
            
            //--2021-09-04
            //
            profit_zz_total = (next_icount - position_x) * Profit_down_Percent;
            
            double rate_gap = buy_rate - sell_rate;
            double keisu_rate = (1-(Gap_down_Percent/100.0));
            
            sell_Lots *= (1+(Profit_down_Percent/100.0));
            sell_Lots += (keisu_pulus_pips*next_icount);
            
            double sell_ratex = buy_rate - ((buy_rate - sell_rate)*(1-(Gap_down_Percent/100.0)));
            
            printf("SELL next_icount=%d,position_x=%d,profit_zz_total=%f",next_icount,position_x,profit_zz_total);
            sell_rate = sell_ratex;
            
         }
      }
      
      //if(OrdersTotal() == LosCutPosition) sell_Lots = Lots;
      
      //sell_Lots = int(sell_Lots);
      
      sell_Lots = NormalizeDouble(sell_Lots,2);
      sell_rate = NormalizeDouble(sell_rate,5);
      
      
      
      next_Finish_Flag  = 0;
      All_lots += sell_Lots;
      if(All_lots >= lot_seigen)  next_Finish_Flag = 1;
      if(All_position >= lot_pos_seigen)  next_Finish_Flag = 1;
      
      
      if(next_Finish_Flag == 0) { 
         bool res = OrderSend(
                    Symbol(),      // 現在の通貨ペア
                    OP_SELLSTOP,   // ロングエントリー(指値)
                    sell_Lots,     // ロット設定
                    sell_rate,     // 
                    3,             // スリップページ
                    0,             // ストップロス設定：無し
                    0,    // リミット設定：無し
                    "SHORT",       // コメント
                    Order_MAGIC,   // マジックナンバー
                    0,             // 有効期限：無し
                    clrRed);       // チャート上の注文矢印の色
         //
         int  res_Error = GetLastError();
         printf("NEXT OP_SELLSTOP sell_rate=%f sell_Lots=%f res_Error=%d",Bid,sell_Lots,res_Error);
      }
   }
}
//
//--TrailingStop
//
void TrailingStop(){
   
   if(TrailingStop_Flag == 1 && OrdersTotal() == 0) {
      TrailingStop_Flag = 0;
      AllDelete();
   } else
   
   for (int i = OrdersTotal() - 1; i >= 0; i--){
      
      if( OrderSelect(i,SELECT_BY_POS,MODE_TRADES) == false) {
         break;
      } else
      
      if (OrderType() == OP_BUY){
         if (OrderStopLoss() < OrderOpenPrice() || OrderStopLoss() == 0){
            double profit = OrderClosePrice() - OrderOpenPrice();
            if (profit / Pips() > trailLength){
               bool res = OrderModify(OrderTicket(), OrderClosePrice(), OrderOpenPrice(), OrderTakeProfit(), OrderExpiration());
            }
         }else{  
            double profit = OrderClosePrice() - OrderStopLoss();
            if (profit / Pips() > trailLength * 2){
               double newStopLoss = OrderStopLoss() + trailLength * Pips();
               bool res = OrderModify(OrderTicket(), OrderClosePrice(), newStopLoss, OrderTakeProfit(), OrderExpiration());
            }
         }
      } else
      
      if (OrderType() == OP_SELL){
         if (OrderStopLoss() > OrderOpenPrice() || OrderStopLoss() == 0){
            double profit = OrderOpenPrice() - OrderClosePrice();
            if (profit / Pips() > trailLength){
               bool res = OrderModify(OrderTicket(), OrderClosePrice(), OrderOpenPrice(), OrderTakeProfit(), OrderExpiration());
            }
         }else{
            double profit = OrderStopLoss() - OrderClosePrice();
            if (profit / Pips() > trailLength * 2){
               double newStopLoss = OrderStopLoss() - trailLength * Pips();
               bool res = OrderModify(OrderTicket(), OrderClosePrice(), newStopLoss, OrderTakeProfit(), OrderExpiration());
            }
         }
      }
   }
}
//
//--Pips
//
double Pips(){

   int digits = (int)MarketInfo(Symbol(), MODE_DIGITS);

   if(digits == 3 || digits == 5){
     return NormalizeDouble(Point * 10, digits - 1);
   }
   if(digits == 4 || digits == 2){
     return Point;
   }
   return 0.1;
}
//
//--TrailingStop_Control
//
void TrailingStop_Control() {

   //
   //--TrailingStop Control
   //
   
   TrailingStop_Flag = 0;
   //
   LastTicket = 0;
   LastLots = 0;
   for (int icount = 0; icount < OrdersTotal(); icount++) {
      if( OrderSelect(icount,SELECT_BY_POS,MODE_TRADES) == false) {
         break;
      } else
      if( OrderSymbol() == Symbol() && OrderMagicNumber() == Order_MAGIC ) {
         if(OrderType() == OP_SELL || OrderType() == OP_BUY) {
            if(LastTicket == 0) {
               LastTicket = OrderTicket();
               LastLots = OrderLots();
            } else
            if(LastLots < OrderLots()) {
               LastTicket = OrderTicket();
               LastLots = OrderLots();
            }
         }
      }
   }
   
   
   //
   for(int loop=0; loop<5; loop++) {
      int end_i =  OrdersTotal() - 1;
      for (int icount = end_i; icount >= 0; icount--) {
         if( OrderSelect(icount,SELECT_BY_POS,MODE_TRADES) == false) {
            break; // 注文選択に失敗したらループ処理終了
         } else
         if( OrderSymbol() == Symbol() && OrderMagicNumber() == Order_MAGIC ) {
            if(LastTicket != OrderTicket()) {
               //
               //--Sell Delete
               //
               if(OrderType()==OP_SELL) {
                  bool  res = OrderClose(
                  OrderTicket(),
                  OrderLots(),
                  Ask,
                  3,
                  clrWhite);
               } else
               if(OrderType()==OP_SELLSTOP) {
                  bool  res = OrderDelete(OrderTicket(),clrNONE);
               }
          
               //
               //--Buy Delete
               //
               if(OrderType()==OP_BUY) {
                  bool  res = OrderClose(
                     OrderTicket(),
                     OrderLots(),
                     Bid,
                     3,
                     clrWhite);
               } else
               if(OrderType()==OP_BUYSTOP) {
                  bool  res = OrderDelete(OrderTicket(),clrNONE);
               }
            }
         }
      }
   }
   
   if(LastTicket != 0 && OrdersTotal() == 1) {
      //
      //--Trailing Start
      //
      TrailingStop_Flag = 1;
      TrailingStop();
   }
}
//
//--Order All Delete
//
void AllDelete() {
   
   //
   //--All Delete
   //
   all_delete_flag   = 1;
   //
   for(int loop=0; loop<5; loop++) {
      int end_i =  OrdersTotal() - 1;
      for (int icount = end_i; icount >= 0; icount--) {
         if( OrderSelect(icount,SELECT_BY_POS,MODE_TRADES) == false) {
            break; // 注文選択に失敗したらループ処理終了
         } else
         if( OrderSymbol() == Symbol() && OrderMagicNumber() == Order_MAGIC ) {
            //
            //--Sell Delete
            //
            if(OrderType()==OP_SELL) {
               bool  res = OrderClose(
               OrderTicket(),
               OrderLots(),
               Ask,
               3,
               clrWhite);
            } else
            if(OrderType()==OP_SELLSTOP) {
               bool  res = OrderDelete(OrderTicket(),clrNONE);
            }
          
            //
            //--Buy Delete
            //
            if(OrderType()==OP_BUY) {
               bool  res = OrderClose(
                  OrderTicket(),
                  OrderLots(),
                  Bid,
                  3,
                  clrWhite);
            } else
            if(OrderType()==OP_BUYSTOP) {
               bool  res = OrderDelete(OrderTicket(),clrNONE);
            }
         }
      }
   }
   
   //
   //--Initialize
   //
   Order_MAGIC       = MAGIC;
   First_Order       = 0;        //--1:Buy 2:Sell
   Next_Order        = 0;        //--1:Buy 2:Sell
   Next_No           = 0;        //--Order No
   rieki_flag        = 0;
   first_rate        = 0;
   order_rate        = 0;
   total_nariyuki    = 0;
   //
   Plus_Flag         = 0;
   //
   profit_zz_total    = 0;
}
//
//--StopOrder Delete
//
void StopOrderDelete() {
   //
   //--Stop Order Delete
   //
   for(int loop=0; loop<5; loop++) {
     for (int icount = 0; icount < OrdersTotal(); icount++) {
       if( OrderSelect(icount,SELECT_BY_POS,MODE_TRADES) == false) {
            break; // 注文選択に失敗したらループ処理終了
       } else
       if( OrderSymbol() == Symbol() && OrderMagicNumber() == Order_MAGIC ) {

          if(OrderType()==OP_SELLSTOP) {
            bool  res = OrderDelete(OrderTicket(),clrNONE);
          } else
          if(OrderType()==OP_BUYSTOP) {
            bool  res = OrderDelete(OrderTicket(),clrNONE);
          }

       }
     }
   }   
}