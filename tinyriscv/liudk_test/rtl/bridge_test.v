/*
 * bridge_test.v

 *
 * Only the RIB-side signals are exposed at the top level.
 *
 * 注意：本文件假设的目录结构与其他源文件一致，即 defines.v 位于 ../core/ 下。
 * 如果你的目录结构不同，请同步修改下面的 `include 路径。
 */

`include "defines.v"
`timescale 1ns/10ps

module bridge_test () ;

    reg                   tb_clk ;
    reg                   tb_rst ;

    reg                   tb_rib_req_i ;    // 请求标志
    reg                   tb_rib_we_i ;     // 写使能
    reg  [`MemAddrBus]    tb_rib_addr_i ;   // 访问地址
    reg  [`MemBus]        tb_rib_data_i ;   // 写入数据
    wire [`MemBus]        tb_rib_data_o ;   // 读出数据

    bridge_top u_bridge_top (

        .clk ( tb_clk ),
        .rst ( tb_rst ),

        .rib_req_i  ( tb_rib_req_i  ),
        .rib_we_i   ( tb_rib_we_i   ),
        .rib_addr_i ( tb_rib_addr_i ),
        .rib_data_i ( tb_rib_data_i ),
        .rib_data_o ( tb_rib_data_o )

    ) ;

    always begin
        #5 ;
        tb_clk = ~tb_clk ;
    end

    initial begin

        $monitor ( " time = %3t | tb_rib_req_i = %b | tb_rib_we_i = %b | tb_rib_addr_i = %h | tb_rib_data_i = %h | tb_rib_data_o = %h " , 
                    $time, tb_rib_req_i, tb_rib_we_i, tb_rib_addr_i, tb_rib_data_i, tb_rib_data_o ) ;

        # 0 ;
        tb_clk        = 1'b0 ;
        tb_rst        = `RstDisable ;
        tb_rib_req_i  = `RIB_NREQ ;
        tb_rib_we_i   = 1'b0 ;
        tb_rib_addr_i = 0 ;
        tb_rib_data_i = 0 ;

        #10 ;
        tb_rst        = `RstEnable ;
        #20 ;
        tb_rst        = `RstDisable ;

        tb_rib_req_i  = `RIB_REQ ;
        tb_rib_we_i   = 1'b1 ;
        tb_rib_addr_i = 32'h0000_0000 ;
        tb_rib_data_i = 32'h1234_5678 ;

        #110 ;
        tb_rib_req_i  = `RIB_NREQ ;
        tb_rib_we_i   = 1'b0 ;
        tb_rib_addr_i = 32'h0000_0000 ;
        tb_rib_data_i = 32'hffff_ffff ;

	#30 ;
        tb_rib_req_i  = `RIB_REQ ;
        tb_rib_we_i   = 1'b1 ;
        tb_rib_addr_i = 32'h0000_0008 ;
        tb_rib_data_i = 32'h2233_8899 ;

        #110 ;
        tb_rib_req_i  = `RIB_NREQ ;
        tb_rib_we_i   = 1'b0 ;
        tb_rib_addr_i = 32'h0000_0000 ;
        tb_rib_data_i = 32'hffff_ffff ;

        #30 ;
        tb_rib_req_i  = `RIB_REQ ;
        tb_rib_we_i   = 1'b0 ;
        tb_rib_addr_i = 32'h0000_0000 ;
        tb_rib_data_i = 32'hffff_ffff ;

        #115 ;
        tb_rib_req_i  = `RIB_NREQ ;

        #35 ;
        tb_rib_req_i  = `RIB_REQ ;
        tb_rib_we_i   = 1'b0 ;
        tb_rib_addr_i = 32'h0000_0008 ;
        tb_rib_data_i = 32'hffff_ffff ;

        #115 ;
        tb_rib_req_i  = `RIB_NREQ ;

	#50 ;

	$finish ;       



    end

    initial begin
	$fsdbDumpfile("bridge_test.fsdb") ;
	$fsdbDumpvars(0,bridge_test) ;
	$fsdbDumpMDA(0,bridge_test) ;
    end

endmodule
