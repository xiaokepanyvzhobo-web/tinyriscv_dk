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
module temp_test
(
input                   sys_clk,                    //system clock 50Mhz on board
input                   rst_n,                      //reset ,low active
output                  scl,                        // LM75 I2C clk
inout                   sda,                        //LM75 I2C data
output [7:0]            SMG_Data,                   //Digital tube segment control line 
output [5:0]            Scan_Sig                    //Bit selection 
);
wire                   done;
wire[16:0]             data;                        //LM75 data
wire[19:0]             bcd_Temp;                    //
/*********************************************************************************
LM75 temperature conversion module, data complement output
**********************************************************************************/
i2c_read_lm75 U0
(
.sys_clk                (sys_clk            ),
.rst_n                  (rst_n              ),
.scl                    (scl                ),
.sda                    (sda                ),
.data                   (data               )
);
/*********************************************************************************
Temperature data for BCD code conversion
**********************************************************************************/
hextobcd U1
(
.clk                    (sys_clk            ),
.hex                    (data               ),
.dec                    (bcd_Temp           )
);
/*********************************************************************************
Temperature data for BCD code conversion
**********************************************************************************/
smg_interface U2
(
.sys_clk                (sys_clk            ),
.rst_n                  (rst_n              ),
.sign                   (data[16]           ),
.Number_Sig             (bcd_Temp           ),          // input - from U1
.SMG_Data               (SMG_Data           ),          // output - to top
.Scan_Sig               (Scan_Sig           )           // output - to top
);
endmodule 
