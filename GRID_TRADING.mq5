//+------------------------------------------------------------------------+
//|                                                     GRID TRADING.mq5   |
//|                   10.05.2022 г.   Copyright 2022, ROMAN SHIREDCHENKO   |
//|                                                http://www.mql5.com     |
//+------------------------------------------------------------------------+
#property copyright "Copyright 2022, ROMAN SHIREDCHENKO "
#property link      "http://www.mql5.com"
#property version   "1.00"
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\AccountInfo.mqh>

//+------------------------------------------------------------------+
//|                          EXTERNAL GRID VARIABLES
//+------------------------------------------------------------------+
input int Volume = 1;                          //Contract/lot volume
input double HIGH_PRICE_SellLim = 5500.00;     //HIGH_PRICE_SellLim (the upper price of the last SellLim grid order)
input double LOW_PRICE_BuyLim  = 4000.00;      //LOW_PRICE_BuyLim   (the lower price of the last BuyLim grid order) for BuyLim
input double HIGH_PRICE_SL  = 100.00;          // HIGH_PRICE_SL: SL in points from HIGH_PRICE_SellLim (the upper stop loss price) for SellLim
input double LOW_PRICE_SL = 100.00;            // LOW_PRICE_SL:  SL in points from LOW_PRICE_BuyLim (lower stop loss price)  for BuyLim
input int Pending_order_period  = 12;          // Pending_order_period: limit order setting time in months
input int Number_of_elements_in_the_grid = 5;  // Number of elements in the grid (number of limit orders)
input double TakeProfit  = 0;                  // TakeProfit from the setting price in order pips
input double Profit_percentage = 1;            // Profit_percentage - grid closure % in profit,  works if > "0"
input  bool Continued_trading = false;         // Continued_trading - whether to continue trading after exiting by the grid closure % with profit

input int    Time_to_restrict_trade  = 5;      // Time_to_restrict_trade - setting the expiration time (in days) for a position with profit
// (exiting the market upon the period end in days)
input int Magic       = 10;                    // Magic Number



//---------------------------------------------------------------------------------------
#define YEAR_SECONDS 31536000
#define MONTH_SECONDS 2419200
#define DAY_SECONDS 86400
#define HOUR_SECONDS 3600
#define MINUTE_SECONDS 60
int Spread;
int N = 0, N_B = 0, N_S = 0, sl_B = 0, sl_S = 0; // N - total accounting of all orders,
int  N_B_previous_num = 0, N_S_previous_num = 0; // starting quantities when placing orders, their values should be reset explicitly in the code text

double step_width = 0; // grid step width
bool flag_buy_pos = false, flag_sell_pos = false; // position absence/presence flags
bool  Grid_start_flag_by_market_position = false; // reset
bool Supporting_contintnued_trading  = false;
bool flag_margin=false;
bool supporting_flag_margin = false;
double fm = 0; // related variables

bool flag_Profit_percentage = false;// related variables
double balance_at_the_start = 0; // related variables

double margin_amount_grid = 0;   // total grid margin

int j=0;
datetime TimeLastBar;

CAccountInfo account;
CTrade trade;
CPositionInfo a_position;
//--- an object for receiving symbol properties
CSymbolInfo symbol_info;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(Magic);//set the magic number for positions

//--- get the number of the account the EA is running on
   long login=account.Login();
   Print("Login=",login);
//--- print the account currency
   Print("Account currency: ",account.Currency());
//--- print balance and current5 profit on the account
   Print("Balance=",account.Balance(),"  Profit=",account.Profit(),"   Equity=",account.Equity());
//--- print account type
   Print("Account type: ",account.TradeModeDescription());
//--- find out whether trading is allowed on this account
   if(account.TradeAllowed())
      Print("Trading on the account is allowed");
   else
      Print("Trading on the account is not allowed: probably connected in with an investor password");
//--- Margin calculation mode
   Print("Margin calculation mode: ",account.MarginModeDescription());
//--- check if trading using Expert Advisors is allowed on the account
   if(account.TradeExpert())
      Print("Automate trading on the account is allowed");
   else
      Print("Automated trading using Expert Advisors or scripts is not allowed");
//--- is the maximum number of orders specified or not
   int orders_limit=account.LimitOrders();
   if(orders_limit!=0)
      Print("The maximum allowable number of actual pending orders: ",orders_limit);
//--- print the name of the company and the name of the server
   Print(account.Company(),": server ",account.Server());
   Print(__FUNCTION__,"  completed");
//---
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {

  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   double Margin = 0;
   int N_B_current_num = 0, N_S_current_num = 0; // current number of limit orders - close the grid if there are none
   int Buy_current_pos = 0, Sell_current_pos = 0; // current number of limit orders - close the grid if there are none
   int i;
   int orders;

   if(!NewBarDetect())
      return;

   while(j==0)
     {
      //--- Setting the name of the symbol, for which we want to obtain information
      symbol_info.Name(_Symbol);
      //--- get current quotes and printing them
      symbol_info.RefreshRates();
      Print(symbol_info.Name()," (",symbol_info.Description(),")",
            "  Bid=",symbol_info.Bid(),"   Ask=",symbol_info.Ask());
      //--- get the number of decimal places and the point value
      Print("Digits=",symbol_info.Digits(),
            ", Point=",DoubleToString(symbol_info.Point(),symbol_info.Digits()));
      //--- request order execution type, check restrictions
      Print("Restrictions on trading operations: ",EnumToString(symbol_info.TradeMode()),
            " (",symbol_info.TradeModeDescription(),")");
      //--- check trade execution modes
      Print("Trade execution mode: ",EnumToString(symbol_info.TradeExecution()),
            " (",symbol_info.TradeExecutionDescription(),")");
      //--- find out how the value of contracts is calculated
      Print("Calculating contract value: ",EnumToString(symbol_info.TradeCalcMode()),
            " (",symbol_info.TradeCalcModeDescription(),")");
      //--- contract size
      Print("Standard contract size: ",symbol_info.ContractSize());
      //--- Value of initial margin per 1 contract
      Print("Initial margin for a standard contract: ",symbol_info.MarginInitial()," ",symbol_info.CurrencyBase());
      //--- minimum and maximum volume size in trading operations
      Print("Volume info: LotsMin=",symbol_info.LotsMin(),"  LotsMax=",symbol_info.LotsMax(),
            "  LotsStep=",symbol_info.LotsStep());
      //---
      Print(__FUNCTION__,"  completed");

      j++;
     }

//-----------  Info messages --------------------------------------------------------------

// user error handling
   double a=SymbolInfoDouble(_Symbol,SYMBOL_ASK);             // current buy price
   double b=SymbolInfoDouble(_Symbol,SYMBOL_BID);             // current sell price
   if(NormalizeDouble((HIGH_PRICE_SellLim - LOW_PRICE_BuyLim)/(Number_of_elements_in_the_grid-1),0) <=
      (a-b))
     {
      Alert(" grid step width comparable to spread of ", _Symbol);
      Alert(" decrease the number of orders in grid or  ");
      Alert(" increase traded range  ");
      return;
     }

//----------------  calculating values before launch     -----------------------------

   if(!supporting_flag_margin)       // Free funds available for opening a position on an account in the deposit currency
     {
      fm = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      Print(" ПЕРЕД СТАРТОМ free_margin = ",  AccountInfoDouble(ACCOUNT_MARGIN_FREE));
      supporting_flag_margin = true; // set the flag since the free margin is constantly recalculated
     }

   if(!flag_Profit_percentage)       // Free funds available for opening a position on an account in the deposit currency
     {
      balance_at_the_start = AccountInfoDouble(ACCOUNT_BALANCE);
      Print(" ПЕРЕД СТАРТОМ balance_at_the_start = ",  AccountInfoDouble(ACCOUNT_BALANCE));
      flag_Profit_percentage = true; // set the flag since the free margin is constantly recalculated
     }


//-------------------  CLOSE BY TIME IN THE MARKET   -------------------------------------------------------
   if(Time_to_restrict_trade > 0) // if closing by time limit in the market in days
      if(PositionSelect(_Symbol))
        {
         Print(" PositionGetInteger(POSITION_TIME) = ",  PositionGetInteger(POSITION_TIME));
         Print(" PositionGetDouble(POSITION_PROFIT) = ", PositionGetDouble(POSITION_PROFIT));
         Print(" PositionGetInteger(POSITION_TIME) + DAY_SECONDS * Time_to_restrict_trade = ", PositionGetInteger(POSITION_TIME) + DAY_SECONDS * Time_to_restrict_trade);
         Print(" TimeCurrent() = ", TimeToString(TimeCurrent()));

         if(PositionGetDouble(POSITION_PROFIT) > 0)
            if(PositionGetInteger(POSITION_TIME) + DAY_SECONDS * Time_to_restrict_trade < TimeCurrent())
              {
               Print(" Close by timer in days per symbol ", _Symbol);
               Print(" Deleting remaining pending orders ");

               // close market position
               for(i = PositionsTotal()-1; i>=0; i--)
                  if(Symbol()==PositionGetSymbol(i))
                     if(a_position.SelectByIndex(i))
                        if(PositionGetInteger(POSITION_MAGIC)==Magic)
                           //--- close the position on the current symbol
                           if(!trade.PositionClose(_Symbol))
                             {
                              //--- report the failure
                              Print("PositionClose() method failed. Return code=",trade.ResultRetcode(),
                                    ". Code description: ",trade.ResultRetcodeDescription());

                              if(Errors(GetLastError())==false)// If the error is insurmountable
                                 return;                       // .. leave.
                             }
                           else
                             {
                              Print("PositionClose() method executed successfully. Return code=",trade.ResultRetcode(),
                                    " (",trade.ResultRetcodeDescription(),")");
                             }

               // remove orders
               for(i = OrdersTotal()-1; i>=0; i--)
                 {
                  ResetLastError();
                  //--- copy the order to the cache by its index in the list
                  ulong ticket=OrderGetTicket(i);
                  if(ticket!=0)// if the order has been successfully copied to cache, handle it
                    {

                     double price_open  =OrderGetDouble(ORDER_PRICE_OPEN);
                     datetime time_setup=OrderGetInteger(ORDER_TIME_SETUP);
                     string symbol      =OrderGetString(ORDER_SYMBOL);
                     int magic_number  =OrderGetInteger(ORDER_MAGIC);
                     if(magic_number==Magic) //  handle the order with the specified ORDER_MAGIC
                        // trying to remove an order
                        if(!trade.OrderDelete(ticket))
                          {
                           //--- report the failure
                           Print("OrderDelete() method failed. Return code=",trade.ResultRetcode(),
                                 ". Code description: ",trade.ResultRetcodeDescription());

                           if(Errors(GetLastError())==false)// If the error is insurmountable
                              return;                       // .. leave.
                          }
                        else
                          {
                           Print("OrderDelete() executed successfully. Return code=",trade.ResultRetcode(),
                                 " (",trade.ResultRetcodeDescription(),")");
                          }
                    }
                 }

              } //    to if ((PositionGetInteger(POSITION_TIME) + DAY_SECONDS * Time_to_restrict_trade < TimeCurrent())

        }


//-------------------------------------------  CLOSING GRID BY PROFIT % --------------------------

   if(Profit_percentage > 0) // if closing by profit %
      if(balance_at_the_start +  balance_at_the_start * Profit_percentage/100 < AccountInfoDouble(ACCOUNT_BALANCE) ||
         balance_at_the_start +  balance_at_the_start * Profit_percentage/100 < AccountInfoDouble(ACCOUNT_EQUITY))
        {
         Print(" Closing by profit % per symbol ", _Symbol);
         Print(" Deleting remaining pending orders ");
         if(Continued_trading == false)
            Supporting_contintnued_trading = true;
         // close market position
         for(i = PositionsTotal()-1; i>=0; i--)
            if(Symbol()==PositionGetSymbol(i))
               if(a_position.SelectByIndex(i))
                  if(PositionGetInteger(POSITION_MAGIC)==Magic)
                     //--- close the position on the current symbol
                     if(!trade.PositionClose(_Symbol))
                       {
                        //--- report the failure
                        Print("PositionClose() method failed. Return code=",trade.ResultRetcode(),
                              ". Code description: ",trade.ResultRetcodeDescription());

                        if(Errors(GetLastError())==false)// If the error is insurmountable
                           return;                       // .. leave.
                       }
                     else
                       {
                        Print("PositionClose() method executed successfully. Return code=",trade.ResultRetcode(),
                              " (",trade.ResultRetcodeDescription(),")");
                       }

         // remove orders
         for(i = OrdersTotal()-1; i>=0; i--)
           {
            ResetLastError();
            //--- copy the order to the cache by its index in the list
            ulong ticket=OrderGetTicket(i);
            if(ticket!=0)// if the order has been successfully copied to cache, handle it
              {

               double price_open  =OrderGetDouble(ORDER_PRICE_OPEN);
               datetime time_setup=OrderGetInteger(ORDER_TIME_SETUP);
               string symbol      =OrderGetString(ORDER_SYMBOL);
               int magic_number  =OrderGetInteger(ORDER_MAGIC);
               if(magic_number==Magic) //  handle the order with the specified ORDER_MAGIC
               //--- trying to remove an order
                  if(!trade.OrderDelete(ticket))
                    {
                     //--- report the failure
                     Print("OrderDelete() method failed. Return code=",trade.ResultRetcode(),
                           ". Code description: ",trade.ResultRetcodeDescription());

                     if(Errors(GetLastError())==false)// If the error is insurmountable
                        return;                       // .. leave.
                    }
                  else
                    {
                     Print("OrderDelete() executed successfully. Return code=",trade.ResultRetcode(),
                           " (",trade.ResultRetcodeDescription(),")");
                    }
              }
           }

        } // if(balance_at_the_start +  balance_at_the_start * Profit_percentage/100 <

// 4. REMOVING GRID - if the price goes beyond the price limits of upper and lower orders, and stop loss is triggered or a loss-making market
// position is closed
//------------------------------ REMOVING GRID ------------------------
//----------------------------------------- when going beyond the border -------------------------------------------

   for(i = PositionsTotal()-1; i>=0; i--)
      if(Symbol()==PositionGetSymbol(i))
         if(a_position.SelectByIndex(i))
           {
            ResetLastError();
            //--- copy a position to the cache by its index in the list
            string symbol=PositionGetSymbol(i); //  get the name of the symbol, by which the position has been opened, along the way
            if(symbol!="") // position copied to cache, processing
              {
               long pos_id            =PositionGetInteger(POSITION_IDENTIFIER);
               double price           =PositionGetDouble(POSITION_PRICE_OPEN);
               ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
               long pos_magic         =PositionGetInteger(POSITION_MAGIC);
               string comment         =PositionGetString(POSITION_COMMENT);
               if(pos_magic==Magic)
                 {
                  //  handle the position with the specified POSITION_MAGIC
                  if(type == POSITION_TYPE_BUY)
                     Buy_current_pos++;
                  if(type == POSITION_TYPE_SELL)
                     Sell_current_pos++;
                 }

              }
            else           // PositionGetSymbol() call failed
              {
               PrintFormat("Failed to get position with index %d. to cache"+
                           " Error code: %d", i, GetLastError());
              }
           }

   if(Buy_current_pos  == 0 && Price_of_orders(0) == 0)

      //  no buy position and no buy limit orders - remove sell - limits
      //--- check if the order exists
      for(i = OrdersTotal()-1; i>=0; i--)
        {
         ResetLastError();
         //--- copy the order to the cache by its index in the list
         ulong ticket=OrderGetTicket(i);
         if(ticket!=0)// if the order has been successfully copied to cache, handle it
           {
            double price_open  =OrderGetDouble(ORDER_PRICE_OPEN);
            datetime time_setup=OrderGetInteger(ORDER_TIME_SETUP);
            string symbol      =OrderGetString(ORDER_SYMBOL);
            int magic_number  =OrderGetInteger(ORDER_MAGIC);

            //--- Everything is ready, trying to delete the order
            if(magic_number==Magic)
               if(!trade.OrderDelete(ticket))
                 {
                  //--- report the failure
                  Print("OrderDelete() method failed. Return code=",trade.ResultRetcode(),
                        ". Code description: ",trade.ResultRetcodeDescription());

                  if(Errors(GetLastError())==false)// If the error is insurmountable
                     return;                       // .. leave.
                 }
               else
                 {
                  Print("OrderDelete() executed successfully. Return code=",trade.ResultRetcode(),
                        " (",trade.ResultRetcodeDescription(),")");
                 }
           }
        } // finished deleting orders


   if(Sell_current_pos == 0 && Price_of_orders(1) == 1000000)
      // no sell position and no buy limit orders - remove sell - limits
      //--- check if the order exists
      for(i = OrdersTotal()-1; i>=0; i--)
        {
         ResetLastError();
         //--- copy the order to the cache by its index in the list
         ulong ticket=OrderGetTicket(i);
         if(ticket!=0)// if the order has been successfully copied to cache, handle it
           {
            double price_open  =OrderGetDouble(ORDER_PRICE_OPEN);
            datetime time_setup=OrderGetInteger(ORDER_TIME_SETUP);
            string symbol      =OrderGetString(ORDER_SYMBOL);
            int magic_number  =OrderGetInteger(ORDER_MAGIC);

            if(magic_number==Magic)
               //--- Everything is ready, trying to delete the order
               if(!trade.OrderDelete(ticket))
                 {
                  //--- report the failure
                  Print("OrderDelete() method failed. Return code=",trade.ResultRetcode(),
                        ". Code description: ",trade.ResultRetcodeDescription());
                  if(Errors(GetLastError())==false)// If the error is insurmountable
                     return;                       // .. leave.
                 }
               else
                 {
                  Print("OrderDelete() executed successfully. Return code=",trade.ResultRetcode(),
                        " (",trade.ResultRetcodeDescription(),")");
                 }
           }
        } // finished deleting orders
//---------------------------------------------------------------------

//------------------------------------------------------------------------------------
// reset flags, set external variables to zero before re-setting the grid

   if(number_of_orders(Magic) == 0) // drop the grid if outside the market
     {
      N_B_previous_num = 0;
      N_S_previous_num = 0;  // external variables - should be reset explicitly
      flag_margin = 0;
      supporting_flag_margin = false;
      flag_Profit_percentage = false;
      margin_amount_grid= 0;
      fm = 0;
      balance_at_the_start = 0;
      N_B_current_num = 0;
      N_S_current_num = 0;
      N_B = 0;
      N_S = 0;                // set the numbers of external variables to zero
      Grid_start_flag_by_market_position = false;

     }



// 4.1. The message prompting a user to set THE APPROPRIATE RANGE VALUES of the of the minimum and maximum borders of the trading approach
// see the description

   if(!having_a_market_position(Magic))
      if(NormalizeDouble(HIGH_PRICE_SellLim,_Digits) < NormalizeDouble(SymbolInfoDouble(_Symbol,SYMBOL_BID),_Digits) ||
         NormalizeDouble(LOW_PRICE_BuyLim,_Digits) > NormalizeDouble(SymbolInfoDouble(_Symbol,SYMBOL_ASK),_Digits))

         if(NormalizeDouble(HIGH_PRICE_SellLim,_Digits) < NormalizeDouble(SymbolInfoDouble(_Symbol,SYMBOL_ASK),_Digits) ||
            NormalizeDouble(LOW_PRICE_BuyLim,_Digits) > NormalizeDouble(SymbolInfoDouble(_Symbol,SYMBOL_BID),_Digits))
           {
            Alert(" values of the upper and lower grid range are outside the allowable price limits ");
            Alert(" set the values of the HIGH_PRICE_SellLim and LOW_PRICE_BuyLim variables according to the trading approach description ");
            return;
           }
//---------------------------------------------------------------------

// 3. ACTIONS TAKEN WHEN LIMITS ARE ACTIVATED
//--- get the total number of orders
   orders=OrdersTotal();

//--- calculate the previous (STARTING) number of limit orders - when still outside the market
   if(!having_a_market_position(Magic))
      if(N_B_previous_num == 0 && N_S_previous_num == 0)
         for(i = orders-1; i>=0; i--)
           {
            ResetLastError();
            //--- copy the order to the cache by its index in the list
            ulong ticket=OrderGetTicket(i);
            if(ticket!=0)// if the order has been successfully copied to cache, handle it
              {
               double Vol  =OrderGetDouble(ORDER_VOLUME_INITIAL);
               double price_open  =OrderGetDouble(ORDER_PRICE_OPEN);
               datetime time_setup=OrderGetInteger(ORDER_TIME_SETUP);
               string symbol      =OrderGetString(ORDER_SYMBOL);
               int magic_number  =OrderGetInteger(ORDER_MAGIC);
               if(magic_number==Magic)
                 {
                  //  handle the order with the specified ORDER_MAGIC
                  if(OrderGetInteger(ORDER_TYPE)==ORDER_TYPE_BUY_LIMIT)
                    {
                     N_B_previous_num++; // STARTING buy limits calculated

                    }

                  if(OrderGetInteger(ORDER_TYPE)==ORDER_TYPE_SELL_LIMIT)
                    {
                     N_S_previous_num++; // STARTING sell limits calculated

                    }

                  N++; // total number of limit orders calculated - EXTERNAL VARIABLE
                 }

              }

            else         // OrderGetTicket() call failed
              {
               PrintFormat("Failed to get order from list to cache. Error code: %d",GetLastError());
              }

           } 

// fill the grid with orders in case of their activation along the symbol price movement
// refer to the order reset function when triggered
   if(having_a_market_position(Magic) && !Grid_start_flag_by_market_position)
     {
      Grid_start_flag_by_market_position = true;      // set the grid start flag, since we are in the market
      //--- UPDATE FOR FURTHER ACCOUNTING - calculate the number of limit orders
      //--- get the total number of positions
      int positions=PositionsTotal();

      for(i = PositionsTotal()-1; i>=0; i--)
         if(Symbol()==PositionGetSymbol(i))
            if(a_position.SelectByIndex(i))
              {
               ResetLastError();
               //--- copy a position to the cache by its index in the list
               string symbol=PositionGetSymbol(i); //  get the name of the symbol, by which the position has been opened, along the way
               if(symbol!="") // position copied to cache, processing
                 {
                  long pos_id            =PositionGetInteger(POSITION_IDENTIFIER);
                  double price           =PositionGetDouble(POSITION_PRICE_OPEN);
                  ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
                  long pos_magic         =PositionGetInteger(POSITION_MAGIC);
                  string comment         =PositionGetString(POSITION_COMMENT);
                  if(pos_magic==Magic)
                    {
                     //  handle the position with the specified POSITION_MAGIC
                     if(type == POSITION_TYPE_BUY)
                        N_B_previous_num--;
                     if(type == POSITION_TYPE_SELL)
                        N_S_previous_num--;
                    }

                 }
               else           // PositionGetSymbol() call failed
                 {
                  PrintFormat("Failed to get position with index %d. to cache"+
                              " Error code: %d", i, GetLastError());
                 }
              }
      if(PositionSelect(_Symbol))
         Print(" PositionGetInteger(POSITION_TIME) = ", PositionGetInteger(POSITION_TIME));
     }


//---------------------------------------------------------------------------------
   if(Grid_start_flag_by_market_position)
     {
      //--- calculate the number of limit orders
      for(i = orders-1; i>=0; i--)
        {
         ResetLastError();
         //--- copy the order to the cache by its index in the list
         ulong ticket=OrderGetTicket(i);
         if(ticket!=0)// if the order has been successfully copied to cache, handle it
           {

            double price_open  =OrderGetDouble(ORDER_PRICE_OPEN);
            datetime time_setup=OrderGetInteger(ORDER_TIME_SETUP);
            string symbol      =OrderGetString(ORDER_SYMBOL);
            int magic_number  =OrderGetInteger(ORDER_MAGIC);
            if(magic_number==Magic) //  handle the order with the specified ORDER_MAGIC
              {
               if(OrderGetInteger(ORDER_TYPE)==ORDER_TYPE_BUY_LIMIT)
                 {
                  N_B_current_num++; // buy limits calculated

                 }

               if(OrderGetInteger(ORDER_TYPE)==ORDER_TYPE_SELL_LIMIT)
                 {
                  N_S_current_num++; // sell limits calculated

                 }

               // N++; // total number of limit orders calculated - EXTERNAL VARIABLE
              }
           }
         else         // OrderGetTicket() call failed
           {
            PrintFormat("Failed to get order from list to cache. Error code: %d",GetLastError());
           }

        }
      }

// further triggers and grid movements after its activation and setting the grid launch by a market position
// Flag_of_grid_launch_by_market_position - when resetting in the market
   if(having_a_market_position(Magic))
      if(Grid_start_flag_by_market_position)
         if(N_B_previous_num != N_B_current_num)  // BUY limit order has apparently been activated and we need to set the next SELL limit order below the previous one using the one
            // closest to the ask price (sell limit grid is increased and moves down to the ask price

           {
            if(Placing_limit_order(1) >=0)
               N_B_previous_num = N_B_current_num;  // the previous value - make it equal to the current one           
           }

   if(having_a_market_position(Magic))
      if(Grid_start_flag_by_market_position)
         if(N_S_previous_num != N_S_current_num)  // SELL limit order has apparently been activated and we need to set the next BUY limit order above the previous one using the one
            // closest to the bid price (grid of BUY limits is increased and moves up to the BID price
           {
            if(Placing_limit_order(0) >= 0)
               N_S_previous_num = N_S_current_num;  // the previous value - make it equal to the current one          
           }


// if the first grid orders, for example buy limit, have been activated and the market position has been closed by sell limit
// if the first buy limit was closed by sell limit - move the buy limit grid upwards
   if(!having_a_market_position(Magic)) // BUY limit order has apparently been activated and has been closed by SELL limit - buy limit should be set higher
      if(N_B_previous_num != N_B_current_num && N_B_current_num > 0)  // ... the grid has been set
        {
         Placing_limit_order(1);
         N_B_previous_num = N_B_current_num;  // the previous value - make it equal to the current one
        }

   if(!having_a_market_position(Magic))
      if(N_S_previous_num != N_S_current_num && N_S_current_num > 0)  // SELL limit order has apparently closed BUY limit order above the previous one using the
         // closest to the bid price (grid of BUY limits is increased and moves up to the BID price
        {
         Placing_limit_order(0);
         N_S_previous_num = N_S_current_num;  // the previous value - make it equal to the current one
        }


   if(Supporting_contintnued_trading == true)
     {
      Alert(" Grid closed/removed to profit by profit % = ", Profit_percentage);
      Alert(" Continued_trading = false; (no more trading) ");
      return;
     }
     
// -----------------------------------------------------------------------
// 1. STARTING SECTION
// setting the starting grid when conditions for its deployment are met according to the calculation of the limit order placement width

   int volume=Volume;
   string symbol= _Symbol;          // specify the symbol the order is to be set on

   int    digits=(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS); // number of decimal places
   double point=SymbolInfoDouble(symbol,SYMBOL_POINT);         // point
   double ask=SymbolInfoDouble(symbol,SYMBOL_ASK);             // current buy price
   double bid=SymbolInfoDouble(symbol,SYMBOL_BID);             // current sell price
   double Price_Start_For_BuyLim = 0;
   double Price_Start_For_SellLim = 0;
   double price = 0;
   int SL_pips, TP_pips;
   double SL, TP;
   datetime    expiration=TimeTradeServer()+Pending_order_period*PeriodSeconds(PERIOD_MN1);
   string comment;

// calculate the grid step  -1. Since the number of orders exceeds the number of steps by 1 as the orders are set at the borders
   step_width =  NormalizeDouble((HIGH_PRICE_SellLim - LOW_PRICE_BuyLim)/(Number_of_elements_in_the_grid-1),0);
   

   if(number_of_orders(Magic) == 0)   // set the grids to long and short in case there are no orders - START
     {
      // setting orders to long - from the lower grid border

      while(N_B < Number_of_elements_in_the_grid)
        {
         //--- placing a pending BuyLimit order with all parameters

         if(N_B==0)
           {
            Price_Start_For_BuyLim = LOW_PRICE_BuyLim;
            price=NormalizeDouble(Price_Start_For_BuyLim,digits);  // open price at the start - normalizing the open price
           }
         if(N_B > 0)
           {
            price = NormalizeDouble(Price_Start_For_BuyLim + N_B * step_width,digits); //  calculated open price by grid steps
           }

         if(HIGH_PRICE_SL > 0)
            SL = NormalizeDouble(LOW_PRICE_BuyLim - LOW_PRICE_SL*point,_Digits);          //  normalized SL value
         else
            SL = 0;

         if(TakeProfit > 0)
            TP=price+TakeProfit*point;                          // unnormalized TP value
         else
            TP=0;
         TP=NormalizeDouble(TP,digits);                      // normalize Take Profit
         expiration=TimeTradeServer()+Pending_order_period*PeriodSeconds(PERIOD_MN1);
         comment=StringFormat("Buy Limit %s %G lots at %s, SL=%s TP=%s",
                              symbol,volume,
                              DoubleToString(price,digits),
                              DoubleToString(SL,digits),
                              DoubleToString(TP,digits));
         //--- everything is ready, sending the pending Buy Limit order to the server
         flag_margin = OrderCalcMargin(ORDER_TYPE_BUY,_Symbol,volume,price,Margin);
         margin_amount_grid = margin_amount_grid + Margin;

         if(price > NormalizeDouble(bid,_Digits))
            break; // if the lower limit prices have reached Bid, exit the loop
         if(!trade.BuyLimit(volume,price,symbol,SL,TP,ORDER_TIME_SPECIFIED_DAY,expiration,0))
           {
            //--- report the failure
            Print("BuyLimit() method failed. Return code=",trade.ResultRetcode(),
                  ". Code description: ",trade.ResultRetcodeDescription());
            if(Errors(GetLastError())==false)// If the error is insurmountable
               return;                       // .. leave.
           }
         else
           {
            Print("BuyLimit() method failed. Return code=",trade.ResultRetcode(),
                  " (",trade.ResultRetcodeDescription(),")");
            N_B++;    // external variable of the number of buy orders
           }

         //------------------------------------
      
        }   //   to while (N_B < Number_of_elements_in_the_grid)



      // place orders to SellLim- short from the upper grid border
      while(N_S < Number_of_elements_in_the_grid)
        {
         //---placing a pending SellLim order with all parameters

         if(N_S==0)
           {
            Price_Start_For_SellLim = HIGH_PRICE_SellLim;
            price=NormalizeDouble(Price_Start_For_SellLim,digits);  // open price at the start - normalizing the open price
           }
         if(N_S > 0)
           {
            price = NormalizeDouble(Price_Start_For_SellLim - N_S * step_width,digits); //  calculated open price by grid steps
           }

         if(HIGH_PRICE_SL > 0)
            SL=NormalizeDouble(HIGH_PRICE_SellLim + HIGH_PRICE_SL*point,_Digits);         // normalized SL value
         else
            SL = 0;

         if(TakeProfit > 0)
            TP = NormalizeDouble(price - TakeProfit*point,_Digits);                       //  normalized TP value
         else
            TP = 0;
         expiration=TimeTradeServer() + Pending_order_period*PeriodSeconds(PERIOD_MN1);
         comment=StringFormat("Sell Limit %s %G lots at %s, SL=%s TP=%s",
                              symbol,volume,
                              DoubleToString(price,digits),
                              DoubleToString(SL,digits),
                              DoubleToString(TP,digits));
         //--- everything is ready, sending the pending Sell Limit order to the server
         flag_margin = OrderCalcMargin(ORDER_TYPE_SELL,_Symbol,volume,price,Margin);
         margin_amount_grid = margin_amount_grid + Margin;

         if(price < NormalizeDouble(ask,_Digits))
            break; //if the grid has reached Ask above the High price, exit the loop

         if(!trade.SellLimit(volume,price,symbol,SL,TP,ORDER_TIME_SPECIFIED_DAY,expiration,0))
           {
            //--- report the failure
            Print("SellLimit() method failed. Return code=",trade.ResultRetcode(),
                  ". Code description: ",trade.ResultRetcodeDescription());

            if(Errors(GetLastError())==false)// If the error is insurmountable
               return;                       // .. leave.
           }
         else
           {
            Print("SellLimit() method executed successfully. Return code=",trade.ResultRetcode(),
                  " (",trade.ResultRetcodeDescription(),")");
            N_S++;
           }

         //------------------------------------

        }   //   to while (N_S < Number_of_elements_in_the_grid)

      Print(" Total number of orders set on a symbol ", _Symbol);            //, " buy positions: ", NormalizeDouble(PositionGetDouble(POSITION_PRICE_OPEN),_Digits));
      Print(" number of orders = ", N_B + N_S, " BUY_LIMIT = ", N_B, " SELL_LIMIT = ", N_S);
      Print(" Order grid step: step_width = ",  step_width);

    }    //  to   if (number_of_orders(Magic) == 0)  // set the grids to long and short in case there are no orders - START
// ---- end of the initial order setting section    -------------------------------------------



// 5. Common section --------------------------------------------------------------

   double MARGIN_INITIAL=AccountInfoDouble(ACCOUNT_MARGIN_INITIAL);
   double margin_position=AccountInfoDouble(ACCOUNT_MARGIN_MAINTENANCE);
   margin_amount_grid = NormalizeDouble(margin_amount_grid,2);
 //  Print(" STARTING free_margin = ",  fm, " CURRENT free_margin = ",  AccountInfoDouble(ACCOUNT_MARGIN_FREE), " MARGIN_INITIAL = ", MARGIN_INITIAL);
 //  Print(" margin_position = ",  margin_position, " MARGIN_INITIAL = ",  MARGIN_INITIAL, " margin_amount_grid = ", margin_amount_grid);
 //  Print(" AccountInfoDouble(ACCOUNT_EQUITY) = ",  AccountInfoDouble(ACCOUNT_EQUITY), " AccountInfoDouble(ACCOUNT_BALANCE) = ",  AccountInfoDouble(ACCOUNT_BALANCE));

// ----------------------------------------------------------------------------------

  }  // end of void OnTick()


//+------------------------------------------------------------------+
//|                             Function of the number of orders by magic number
//+------------------------------------------------------------------+
int number_of_orders(int Magic_) // number of orders by magic number
  {
//--- get the total number of orders
   int ord = 0; // final value of the number of orders
   int orders=OrdersTotal();
//--- go through the list of orders
   for(int i=0; i<orders; i++)
     {
      ResetLastError();
      //--- copy the order to the cache by its index in the list
      ulong ticket=OrderGetTicket(i);
      if(ticket!=0)// if the order has been successfully copied to cache, handle it
        {
         double price_open  =OrderGetDouble(ORDER_PRICE_OPEN);
         datetime time_setup=OrderGetInteger(ORDER_TIME_SETUP);
         string symbol      =OrderGetString(ORDER_SYMBOL);
         long magic_number  =OrderGetInteger(ORDER_MAGIC);
         if(magic_number==Magic_)
           {
            //  handle the order with the specified ORDER_MAGIC - calculate
            ord++;
           }
        }
      else         // OrderGetTicket() call failed
        {
         PrintFormat("Failed to get order from list to cache. Error code: %d",GetLastError());
        }

     }
   return (ord);
  }


//---------------------- return the order type with the setting price closest to the current symbol price   ------------------
//+------------------------------------------------------------------+
//|                       The function of the price of the order closest to the price by magic number
//+------------------------------------------------------------------+
int Price_of_orders(int Tip) // price of the order closest to the price by magic number
  {
//---------------------------------------
   double price_open_buy_lim = 0;
   double price_open_sell_lim = 0;
   datetime time_setup;
   string symbol;
   long magic_number;
   int Tip_ord;
   double PRICE_MAX_Buy_Lim = 0; // maximum value of the last buy limit order
   double PRICE_MIN_Sell_Lim = 1000000; // minimum value of the last sell limit order
   int orders=OrdersTotal();
//--- go through the list of orders
   for(int i=0; i<orders; i++)
     {
      ResetLastError();
      //--- copy the order to the cache by its index in the list
      ulong ticket=OrderGetTicket(i);
      if(ticket!=0)// if the order has been successfully copied to cache, handle it
        {
         Tip_ord = OrderGetInteger(ORDER_TYPE);
         symbol      =OrderGetString(ORDER_SYMBOL);
         magic_number  =OrderGetInteger(ORDER_MAGIC);
         if(magic_number==Magic && symbol == _Symbol)
           {
            if(Tip==0 && Tip_ord == ORDER_TYPE_BUY_LIMIT)  // entered here with "0" via the function and buy limit order
              {
               // select the maximum one by price
               price_open_buy_lim = OrderGetDouble(ORDER_PRICE_OPEN);
               if(PRICE_MAX_Buy_Lim <= price_open_buy_lim)
                  PRICE_MAX_Buy_Lim = price_open_buy_lim;

              }

            if(Tip==1 && Tip_ord == ORDER_TYPE_SELL_LIMIT)  // entered here with "1" via the function and SELL-LIMIT order
              {
               // select MIN by price
               price_open_sell_lim = OrderGetDouble(ORDER_PRICE_OPEN);
               if(PRICE_MIN_Sell_Lim >= price_open_sell_lim)
                  PRICE_MIN_Sell_Lim = price_open_sell_lim;
              }

           }
        }
      else         // OrderGetTicket() call failed
        {
         PrintFormat("Failed to get order from list to cache. Error code: %d",GetLastError());
        }
     }

   if(Tip==0)
     {
      Print(" function Price_of_orders: PRICE_MAX_Buy_Lim = ", PRICE_MAX_Buy_Lim);
      return(PRICE_MAX_Buy_Lim);
     }
   if(Tip==1)
     {
      Print(" function Price_of_orders: PRICE_MIN_Sell_Lim = ", PRICE_MIN_Sell_Lim);
      return(PRICE_MIN_Sell_Lim);
     }
   return (-1);
  }

//------------------------------------------------

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool having_a_market_position(int Magic_)    // return the presence/absence of a market position
  {
   bool market_position = false;
//
   for(int i = PositionsTotal()-1; i>=0; i--)
      if(Symbol()==PositionGetSymbol(i))
         if(a_position.SelectByIndex(i))
            if(PositionSelect(Symbol()))
              {
               market_position = true;
              }
   return (market_position);
  }

//+------------------------------------------------------------------+
//|        set a limit order
//+------------------------------------------------------------------+
double Placing_limit_order(int Tip)
// set a limit order when one of them is activated in the grid
// if buy limit is triggered, set a sell limit from the last lower one (fill in the grid with sell limits downwards)
// if sell limit is triggered, set a buy limit from the last upper one (fill in the grid with buy limits upwards)
  {
   int volume=Volume;
   string symbol= _Symbol;                                    // specify the symbol the order is to be set on
   int    digits=(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS); // number of decimal places
   double point=SymbolInfoDouble(symbol,SYMBOL_POINT);         // point
   double ask=SymbolInfoDouble(symbol,SYMBOL_ASK);             // current buy price
   double bid=SymbolInfoDouble(symbol,SYMBOL_BID);             // current sell price
   double Price_Start_For_BuyLim = 0;
   double Price_Start_For_SellLim = 0;
   double price = 0;
   int SL_pips, TP_pips;
   int N_B_fun = 0,  N_S_fun = 0;
   double SL, TP;
   datetime expiration=TimeTradeServer()+ Pending_order_period*PeriodSeconds(PERIOD_MN1);;
   string comment;

// calculate the grid step
   step_width =  NormalizeDouble((HIGH_PRICE_SellLim - LOW_PRICE_BuyLim)/(Number_of_elements_in_the_grid - 1),0);


   if(number_of_orders(Magic) > 0)   // set a single pending order when conditions are triggered in a grid
     {
      //

      if(Tip==0)  // placing orders to long buy limit when a sell limit is triggered
         while(N_B_fun == 0)
           {
            //--- placing a pending BuyLimit order with all parameters

            if(N_B_fun == 0)
              {
               price = NormalizeDouble(Price_of_orders(0) + step_width,digits); //  calculated price of placing the next one by grid steps
               // from the maximum buy limit
              }


            Print("  Placing_limit_order function: N_B_fun in the loop = ", N_B_fun, "  price = ", price);

            if(LOW_PRICE_SL > 0)
               SL= NormalizeDouble(LOW_PRICE_BuyLim - LOW_PRICE_SL*point,_Digits);            // normalized SL value
            else
               SL = 0;

            if(TakeProfit > 0)
               TP = NormalizeDouble(price+TakeProfit*point,_Digits);                          // normalized TP value
            else
               TP=0;
            TP=NormalizeDouble(TP,digits);                      // normalize Take Profit
            expiration=TimeTradeServer()+ Pending_order_period*PeriodSeconds(PERIOD_MN1);
            comment=StringFormat("Buy Limit %s %G lots at %s, SL=%s TP=%s",
                                 symbol,volume,
                                 DoubleToString(price,digits),
                                 DoubleToString(SL,digits),
                                 DoubleToString(TP,digits));
            //--- everything is ready, sending the pending Buy Limit order to the server
            // from the maximum one by price from the previous one
            if(price > NormalizeDouble(bid - (step_width/2),_Digits))
              {
               Print(" Exit Placing_limit_order function: BuyLimit order is not set close to ask = ",ask);
               return(-1); // if the lower limit prices have reached Bid, exit the loop
              }

            if(!trade.BuyLimit(volume,price,symbol,SL,TP,ORDER_TIME_SPECIFIED_DAY,expiration,comment))
              {
               //--- report the failure
               Print("BuyLimit() method failed. Return code=",trade.ResultRetcode(),
                     ". Code description: ",trade.ResultRetcodeDescription());

               if(Errors(GetLastError())==false)// If the error is insurmountable
                  return(-1) ;                       // .. leave.
              }
            else
              {
               Print(" Function of filling the grid with orders when the opposite one is triggered. BuyLimit() method executed successfully. Return code=",trade.ResultRetcode(),
                     " (",trade.ResultRetcodeDescription(),")");
               N_B_fun++;    // external variable of the number of buy orders
               //------------------------------------
              }

           }   //   to while (N_B < Number_of_elements_in_the_grid)



      // setting orders to SellLim short when buy limit is triggered
      if(Tip==1)
         while(N_S_fun ==0)
           {
            //---placing a pending SellLim order with all parameters

            if(N_S_fun == 0)
              {
               price = NormalizeDouble(Price_of_orders(1) - step_width,digits); //  calculated open price by grid steps
              }

            if(HIGH_PRICE_SL > 0)
               SL = NormalizeDouble(HIGH_PRICE_SellLim + HIGH_PRICE_SL*point,_Digits);  // normalized SL value
            else
               SL = 0;

            if(TakeProfit > 0)
               TP = NormalizeDouble(price - TakeProfit*point,_Digits);                // normalized TP value
            else
               TP = 0;

            TP=NormalizeDouble(TP,digits);                      // normalize Take Profit
            expiration=TimeTradeServer() + Pending_order_period*PeriodSeconds(PERIOD_MN1);
            comment=StringFormat("Sell Limit %s %G lots at %s, SL=%s TP=%s",
                                 symbol,volume,
                                 DoubleToString(price,digits),
                                 DoubleToString(SL,digits),
                                 DoubleToString(TP,digits));
            //--- everything is ready, sending the pending Sell Limit order to the server
            // from the minimum one by price of the previous sell limit
            if(price < NormalizeDouble(ask + (step_width/2),_Digits))
              {
               Print(" Exiting the Placing_limit_order function: SELL Limit order is not set close to Bid = ", bid);
               return(-1); // if the lower limit prices have reached Bid, exit the loop
              }


            if(!trade.SellLimit(volume,price,symbol,SL,TP,ORDER_TIME_SPECIFIED_DAY,expiration,comment))
              {
               //--- report the failure
               Print(" SellLimit() method failed. Return code=",trade.ResultRetcode(),
                     ". Code description: ",trade.ResultRetcodeDescription());
               if(Errors(GetLastError())==false)// If the error is insurmountable
                  return(-1);                       // .. leave.
              }
            else
              {
               Print(" Function of filling the grid with orders when the opposite one is triggered. SellLimit() method executed successfully. Return code=",trade.ResultRetcode(),
                     " (",trade.ResultRetcodeDescription(),")");
               N_S_fun++;
              }

            //------------------------------------

           }   //   to while (N_S < Number_of_elements_in_the_grid)

     }    //  to   if (number_of_orders(Magic) == 0)  // set the grids to long and short in case there are no orders - START
   return(Tip);
  }
//+------------------------------------------------------------------+
//| Return true if new bar detect, otherwise return false.           |
//+------------------------------------------------------------------+
bool NewBarDetect()
  {
   datetime times[];
   if(CopyTime(Symbol(),Period(),0,1,times)<1)
      return false;
   if(times[0] == TimeLastBar)
      return false;
   TimeLastBar = times[0];
   return true;
  }
//+------------------------------------------------------------------+


//+------------------------------------------------------------------+
//| convert numeric response codes to string mnemonics               |
//+------------------------------------------------------------------+
bool Errors(int Error)
//--------------------------------------------------------------- 1 --
// Error handling function.
// Returned values:
// true  - if the error is manageable (the work can be resumed)
// false - if the error is critical (trading is not allowed)
//--------------------------------------------------------------- 2 --
  {
   switch(Error)
     {
      case 10004:
         Print("TRADE_RETCODE_REQUOTE");
         symbol_info.RefreshRates();
         Sleep(1000);
         symbol_info.RefreshRates();
         return(true);            // Requote  - Manageable error
      case 10006:
         Print("TRADE_RETCODE_REJECT");
         Sleep(1000);
         symbol_info.RefreshRates();
         return(true);            // Request rejected
      case 10007:
         Alert("TRADE_RETCODE_CANCEL");
         return(false);           // Request canceled by a trader

      case 10008:
         Print("TRADE_RETCODE_PLACED");
         return(false);           // Order placed
      case 10009:
         Print("TRADE_RETCODE_DONE");
         return(false);           // Request completed
      case 10010:
         Print("TRADE_RETCODE_DONE_PARTIAL");
         Sleep(1000);
         symbol_info.RefreshRates();
         return(true); // Request completed partially
      case 10011:
         Print("TRADE_RETCODE_ERROR");
         Sleep(1000);
         symbol_info.RefreshRates();
         return(true); // Request handling error
      case 10012:
         Print("TRADE_RETCODE_TIMEOUT");
         Sleep(1000);
         return(true); // Request expired
      case 10013:
         Alert("TRADE_RETCODE_INVALID");
         return(false);               // Invalid request
      case 10014:
         Alert("TRADE_RETCODE_INVALID_VOLUME");
         return(false);               // Invalid request volume
      case 10015:
         Alert("TRADE_RETCODE_INVALID_PRICE");
         Sleep(1000);
         return(true);    // Invalid request price
      case 10016:
         Alert("TRADE_RETCODE_INVALID_STOPS");
         return(false);               // Invalid request stops
      case 10017:
         Alert("TRADE_RETCODE_TRADE_DISABLED");
         return(false);                // Trading disabled
      case 10018:
         Print("TRADE_RETCODE_MARKET_CLOSED");
         return(false);                // Market closed
      case 10019:
         Alert("TRADE_RETCODE_NO_MONEY");
         return(false); // Insufficient funds for request execution
      case 10020:
         Print("TRADE_RETCODE_PRICE_CHANGED");
         Sleep(1000);
         symbol_info.RefreshRates();
         return(true);     // Price changed
      case 10021:
         Print("TRADE_RETCODE_PRICE_OFF");
         Sleep(1000);
         symbol_info.RefreshRates();
         return(true);  // No quotes to handle the request
      case 10022:
         Alert("TRADE_RETCODE_INVALID_EXPIRATION");
         return(false);  // Invalid order expiration in a request
      case 10023:
         Print("TRADE_RETCODE_ORDER_CHANGED");
         Sleep(1000);
         symbol_info.RefreshRates();
         return(true); // Order status changed
      case 10024:
         Print("TRADE_RETCODE_TOO_MANY_REQUESTS");
         Sleep(1000);
         return(true);  // Too many requests
      case 10025:
         Print("TRADE_RETCODE_NO_CHANGES");
         Sleep(1000);
         return(true); // No changes in request
      case 10026:
         Alert("TRADE_RETCODE_SERVER_DISABLES_AT");
         return(false);   // Auto trading disabled by server
      case 10027:
         Alert("TRADE_RETCODE_CLIENT_DISABLES_AT");
         return(false);  // Auto trading disabled by client terminal
      case 10028:
         Print("TRADE_RETCODE_LOCKED");
         Sleep(1000);
         return(true); // Request blocked for handling
      case 10029:
         Print("TRADE_RETCODE_FROZEN");
         Sleep(1000);
         return(true); // Order or position frozen
      case 10030:
         Alert("TRADE_RETCODE_INVALID_FILL");
         return(false);   // Specified type of order execution by residue not supported
      case 10031:
         Print("TRADE_RETCODE_CONNECTION");
         Sleep(1000);
         return(true);     // No connection to trade server
      case 10032:
         Alert("TRADE_RETCODE_ONLY_REAL");
         return(false);  // Transaction allowed for live accounts only
      case 10033:
         Alert("TRADE_RETCODE_LIMIT_ORDERS");
         return(false);  // Maximum number of pending orders reached
      case 10034:
         Alert("TRADE_RETCODE_LIMIT_VOLUME");
         return(false);  // Maximum order and position volume for symbol reached
      case 10035:
         Alert("TRADE_RETCODE_INVALID_ORDER");
         return(false);  // Invalid or prohibited order type
      case 10036:
         Print("TRADE_RETCODE_POSITION_CLOSED");
         return(false);  // Position with specified POSITION_IDENTIFIER already closed
      default:
         Print("TRADE_RETCODE_UNKNOWN = ", Error);
         Sleep(1000);
         return(true);
     }
  }

//+------------------------------------------------------------------+
