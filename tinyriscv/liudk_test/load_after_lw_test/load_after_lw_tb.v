`timescale 1ns/1ps

`include "defines.v"

module load_after_lw_tb;

    localparam integer CLK_PERIOD_NS = 20;
    localparam integer MAX_CYCLES = 200000;

    reg clk;
    reg rst;
    reg uart_debug_pin;
    reg uart_rx_pin;

    wire succ;
    wire uart_tx_pin;
    tri1 io_sda;
    wire io_scl;

    integer i;
    integer cycle;
    reg pass;
    reg [8*256-1:0] inst_file;

    always #(CLK_PERIOD_NS / 2) clk = ~clk;

    initial begin
`ifndef NO_DUMP
`ifdef FSDB
        $fsdbDumpfile("liudk_test/load_after_lw_test/build/load_after_lw_tb.fsdb");
        $fsdbDumpvars(0, load_after_lw_tb);
        $fsdbDumpMDA(0, load_after_lw_tb);
`else
        $dumpfile("liudk_test/load_after_lw_test/build/load_after_lw_tb.vcd");
        $dumpvars(0, load_after_lw_tb);
`endif
`endif
    end

    initial begin
        clk = 1'b0;
        rst = `RstEnable;
        uart_debug_pin = 1'b0;
        uart_rx_pin = 1'b1;
        pass = 1'b0;
        inst_file = "liudk_test/load_after_lw_test/load_after_lw.data";
        if ($value$plusargs("INST_FILE=%s", inst_file)) begin end

        $readmemh(inst_file, u_dut.u_bridge_slave_top.u_rom._rom);

        for (i = 0; i < `MemNum; i = i + 1) begin
            u_dut.u_bridge_slave_top.u_ram._ram[i] = `ZeroWord;
        end
        u_dut.u_bridge_slave_top.u_ram._ram[35] = 32'h0000006c;

        repeat (20) @(posedge clk);
        rst = `RstDisable;

        cycle = 0;
        while ((cycle < MAX_CYCLES) && !pass) begin
            cycle = cycle + 1;
            @(posedge clk);
            if ((u_dut.u_tinyriscv_soc_top.u_tinyriscv.u_regs.regs[26] == 32'h1) &&
                (u_dut.u_tinyriscv_soc_top.u_tinyriscv.u_regs.regs[6] == 32'h6c) &&
                (u_dut.u_tinyriscv_soc_top.u_tinyriscv.u_regs.regs[7] == 32'h6d) &&
                (u_dut.u_tinyriscv_soc_top.u_tinyriscv.u_regs.regs[2] == 32'h10004000)) begin
                pass = 1'b1;
            end
        end

        if (pass) begin
            $display("[LOAD_AFTER_LW_TB] FINAL PASS");
        end else begin
            $display("[LOAD_AFTER_LW_TB] FINAL FAIL");
        end

        $display("[LOAD_AFTER_LW_TB] x2(sp)=0x%08x x5(t0)=0x%08x x6(t1)=0x%08x x7(t2)=0x%08x x26(s10)=0x%08x",
                 u_dut.u_tinyriscv_soc_top.u_tinyriscv.u_regs.regs[2],
                 u_dut.u_tinyriscv_soc_top.u_tinyriscv.u_regs.regs[5],
                 u_dut.u_tinyriscv_soc_top.u_tinyriscv.u_regs.regs[6],
                 u_dut.u_tinyriscv_soc_top.u_tinyriscv.u_regs.regs[7],
                 u_dut.u_tinyriscv_soc_top.u_tinyriscv.u_regs.regs[26]);

        dump_ram_contents;
        repeat (20) @(posedge clk);
        $finish;
    end

    initial begin
        #(CLK_PERIOD_NS * MAX_CYCLES + 1000);
        $display("[LOAD_AFTER_LW_TB] TIMEOUT");
        $display("[LOAD_AFTER_LW_TB] x2(sp)=0x%08x x5(t0)=0x%08x x6(t1)=0x%08x x7(t2)=0x%08x x26(s10)=0x%08x pc=0x%08x",
                 u_dut.u_tinyriscv_soc_top.u_tinyriscv.u_regs.regs[2],
                 u_dut.u_tinyriscv_soc_top.u_tinyriscv.u_regs.regs[5],
                 u_dut.u_tinyriscv_soc_top.u_tinyriscv.u_regs.regs[6],
                 u_dut.u_tinyriscv_soc_top.u_tinyriscv.u_regs.regs[7],
                 u_dut.u_tinyriscv_soc_top.u_tinyriscv.u_regs.regs[26],
                 u_dut.u_tinyriscv_soc_top.u_tinyriscv.pc_pc_o);
        dump_ram_contents;
        $finish;
    end

    always @(posedge clk) begin
        if ((rst == `RstDisable) &&
            (u_dut.u_tinyriscv_soc_top.u_tinyriscv.final_reg_we == `WriteEnable)) begin
            case (u_dut.u_tinyriscv_soc_top.u_tinyriscv.ex_reg_waddr_o)
                5'd2, 5'd5, 5'd6, 5'd7, 5'd26: begin
                    $display("[LOAD_AFTER_LW_TB] REG_WRITE: pc=0x%08x inst=0x%08x x%0d<=0x%08x ctrl_state=0x%0x",
                             u_dut.u_tinyriscv_soc_top.u_tinyriscv.pc_pc_o,
                             u_dut.u_tinyriscv_soc_top.u_tinyriscv.ie_inst_o,
                             u_dut.u_tinyriscv_soc_top.u_tinyriscv.ex_reg_waddr_o,
                             u_dut.u_tinyriscv_soc_top.u_tinyriscv.ex_reg_wdata_o,
                             u_dut.u_tinyriscv_soc_top.u_tinyriscv.ctrl_state_o);
                end
            endcase
        end
    end

    always @(posedge clk) begin
        if ((rst == `RstDisable) &&
            (u_dut.u_tinyriscv_soc_top.u_tinyriscv.rib_ex_req_o == `RIB_REQ) &&
            (u_dut.u_tinyriscv_soc_top.u_tinyriscv.rib_ex_we_o == `WriteEnable)) begin
            $display("[LOAD_AFTER_LW_TB] STORE_REQ: pc=0x%08x inst=0x%08x addr=0x%08x data=0x%08x ack=%b ctrl_state=0x%0x",
                     u_dut.u_tinyriscv_soc_top.u_tinyriscv.pc_pc_o,
                     u_dut.u_tinyriscv_soc_top.u_tinyriscv.ie_inst_o,
                     u_dut.u_tinyriscv_soc_top.u_tinyriscv.rib_ex_addr_o,
                     u_dut.u_tinyriscv_soc_top.u_tinyriscv.rib_ex_data_o,
                     u_dut.u_tinyriscv_soc_top.u_tinyriscv.rib_ex_ack_i,
                     u_dut.u_tinyriscv_soc_top.u_tinyriscv.ctrl_state_o);
        end
    end

    always @(posedge clk) begin
        if ((rst == `RstDisable) &&
            (u_dut.u_tinyriscv_soc_top.u_tinyriscv.rib_ex_req_o == `RIB_REQ) &&
            (u_dut.u_tinyriscv_soc_top.u_tinyriscv.rib_ex_we_o == `WriteDisable)) begin
            $display("[LOAD_AFTER_LW_TB] LOAD_REQ: pc=0x%08x inst=0x%08x addr=0x%08x data_i=0x%08x ack=%b ctrl_state=0x%0x",
                     u_dut.u_tinyriscv_soc_top.u_tinyriscv.pc_pc_o,
                     u_dut.u_tinyriscv_soc_top.u_tinyriscv.ie_inst_o,
                     u_dut.u_tinyriscv_soc_top.u_tinyriscv.rib_ex_addr_o,
                     u_dut.u_tinyriscv_soc_top.u_tinyriscv.rib_ex_data_i,
                     u_dut.u_tinyriscv_soc_top.u_tinyriscv.rib_ex_ack_i,
                     u_dut.u_tinyriscv_soc_top.u_tinyriscv.ctrl_state_o);
        end
    end

    always @(posedge clk) begin
        if (u_dut.u_bridge_slave_top.u_ram.we_i == `WriteEnable) begin
            $display("[LOAD_AFTER_LW_TB] RAM_WRITE: addr=0x%08x word_index=0x%08x data=0x%08x",
                     u_dut.u_bridge_slave_top.u_ram.addr_i,
                     u_dut.u_bridge_slave_top.u_ram.addr_i[31:2],
                     u_dut.u_bridge_slave_top.u_ram.data_i);
        end
    end

    task dump_ram_contents;
        integer ram_i;
        begin
            $display("[LOAD_AFTER_LW_TB] RAM_DUMP_BEGIN");
            for (ram_i = 0; ram_i < `MemNum; ram_i = ram_i + 1) begin
                $display("[LOAD_AFTER_LW_TB] RAM[%0d] = 0x%08x", ram_i, u_dut.u_bridge_slave_top.u_ram._ram[ram_i]);
            end
            $display("[LOAD_AFTER_LW_TB] RAM_DUMP_END");
        end
    endtask

    tinyriscv_soc_top_with_bridge u_dut(
        .clk(clk),
        .rst(rst),
        .succ(succ),
        .uart_debug_pin(uart_debug_pin),
        .uart_tx_pin(uart_tx_pin),
        .uart_rx_pin(uart_rx_pin),
        .io_sda(io_sda),
        .io_scl(io_scl)
    );

endmodule
