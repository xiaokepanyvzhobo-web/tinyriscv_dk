//////////////////////////////////////////////////////////////////////////////////
//                                                                              //
//                                                                              //
//  Author: lhj                                                                 //
//                                                                              //
//          ALINX(shanghai) Technology Co.,Ltd                                  //
//          heijin                                                              //
//     WEB: http://www.alinx.com/                                               //
//     BBS: http://www.heijin.org/                                              //
//                                                                              //
//////////////////////////////////////////////////////////////////////////////////
//                                                                              //
// Copyright (c) 2017,ALINX(shanghai) Technology Co.,Ltd                        //
//                    All rights reserved                                       //
//                                                                              //
// This source file may be used and distributed without restriction provided    //
// that this copyright statement is not removed from the file and that any      //
// derivative work contains the original copyright notice and the associated    //
// disclaimer.                                                                  //
//                                                                              //
//////////////////////////////////////////////////////////////////////////////////

//================================================================================
//  Revision History:
//  Date          By            Revision    Change Description
//--------------------------------------------------------------------------------
//2019/08/16           lhj         1.0          Original
/*******************************************************************************/
module smg_scan_module
(
 input                  sys_clk, 
 input                  rst_n, 
 output [5:0]           Scan_Sig
);
parameter T1MS        = 16'd49999; //1ms time 
parameter IDLE         =6'b000001;
parameter ST1          =6'b000010;
parameter ST2          =6'b000100;
parameter ST3          =6'b001000;
parameter ST4          =6'b010000;
parameter ST5          =6'b100000;
reg [5:0]              cur_state;
reg [5:0]              next_state;
reg [15:0]             time_cnt;   //time count
reg [5:0]              rScan;      //digital tube scan
assign Scan_Sig = rScan;
always@(posedge sys_clk)
begin 
if(!rst_n)
    cur_state<=IDLE;
 else
    cur_state<=next_state;
end

 always @ ( posedge sys_clk or negedge rst_n )
 begin
     if( !rst_n )
     time_cnt<= 16'd0;
      else if(time_cnt == T1MS )
          time_cnt<= 16'd0;
      else
          time_cnt<=time_cnt+ 1'b1;
end
always @ ( time_cnt or cur_state )
begin
  case(cur_state)    
      IDLE:
         begin
            if(time_cnt== T1MS ) 
                next_state<=ST1;
             else
                next_state<=IDLE;
         end          
      ST1:
         begin
            if(time_cnt== T1MS ) 
                next_state<=ST2;
             else
                next_state<=ST1;
         end    
      ST2:
         begin
            if(time_cnt== T1MS ) 
                next_state<=ST3;
             else
                next_state<=ST2;
         end     
       ST3:
         begin
            if(time_cnt== T1MS ) 
                next_state<=ST4;
             else
                next_state<=ST3;
         end    
      ST4:
         begin
            if(time_cnt== T1MS ) 
                next_state<=ST5;
             else
                next_state<=ST4;
            end
      ST5:
         begin
            if(time_cnt== T1MS ) 
                next_state<=IDLE;
             else
                next_state<=ST5;
         end
       default: next_state<=IDLE;                
    endcase
end
 always @ ( posedge sys_clk or negedge rst_n )
 begin
    if( !rst_n )
      begin
          rScan <= 6'b100_000;
       end
    else 
        case( next_state)    
            IDLE:
                rScan <= 6'b011_111;                      //The first digital tube strobe            
            ST1:
                 rScan <= 6'b101_111;                      //The second digital tube strobe             
            ST2:
                 rScan <= 6'b110_111;                      //The third digital tube strobe              
            ST3:
                 rScan <= 6'b111_011;                      //The fourth digital tube strobe                
            ST4:
                 rScan <= 6'b111_101;                      //The fifth digital tube strobe                
            ST5:
                 rScan <= 6'b111_110;                      //The sixth digital tube strobe 
            default: 
                 rScan <= 6'b100_000;                          
        endcase
 end
endmodule