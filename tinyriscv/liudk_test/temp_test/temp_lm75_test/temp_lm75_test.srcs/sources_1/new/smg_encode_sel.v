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
module smg_encode_sel
(
input [5:0]             Scan_Sig,
input[7:0]              SMG_Data_1,
input[7:0]              SMG_Data_2,
output[7:0]             SMG_Data
);
reg [7:0]               rSMG;
assign  SMG_Data        =rSMG; 
always @ (* )
begin
   case( Scan_Sig )
       
          6'b011_111 :  rSMG <=SMG_Data_1;
          6'b101_111 :  rSMG <=SMG_Data_1;
          6'b110_111:   rSMG <=SMG_Data_1;
          6'b111_011 :  rSMG <=SMG_Data_1;
          6'b111_101:   rSMG <=SMG_Data_2;
          6'b111_110:   rSMG <=SMG_Data_1;
          default:      rSMG <=rSMG;
      endcase
 end          
endmodule
