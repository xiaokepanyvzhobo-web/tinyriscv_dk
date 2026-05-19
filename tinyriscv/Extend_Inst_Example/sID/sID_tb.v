`timescale 1ns/1ps

`include "defines.v"

module sID_tb;

    localparam integer CLK_PERIOD_NS = 20;
`ifdef FAST_UART_SIM
    localparam integer UART_BIT_NS   = 180;
`elsif IVERILOG_FAST_SIM
    localparam integer UART_BIT_NS   = 180;
`else
    localparam integer UART_BIT_NS   = 8820;
`endif
    localparam integer PACKET_LEN = 35;
    localparam integer PAYLOAD_LEN = 32;
    localparam integer MAX_WORDS = 4096;
    localparam integer MAX_BYTES = MAX_WORDS * 4;
    localparam integer SID_LEN = 10;
    localparam integer UART_START_TIMEOUT_CYCLES = 200000;
    localparam [8*SID_LEN-1:0] EXPECTED_ID_TEXT = "2025210905";

    reg clk;
    reg rst;
    reg uart_debug_pin;
    reg uart_rx_pin;

    wire succ;
    wire uart_tx_pin;
    tri1 io_sda;
    wire io_scl;

    reg [31:0] inst_words [0:MAX_WORDS - 1];
    reg [7:0] fw_bytes [0:MAX_BYTES - 1];
    reg [7:0] packet [0:PACKET_LEN - 1];
    reg [7:0] sid_rx [0:SID_LEN - 1];

    reg [8*256-1:0] inst_file;
    reg [8*256-1:0] vcd_file;
    reg [8*256-1:0] rom_dump_file;

    integer fd;
    integer code;
    integer word_count;
    integer fw_size;
    integer total_packets;
    integer i;
    integer wait_cycles;
    integer sid_pass;
    integer sid_uart_write_count;
    reg [31:0] word_tmp;
    reg [15:0] crc;
    reg [7:0] ack;
    reg [7:0] rx_byte;
    reg rx_ok;

    always #(CLK_PERIOD_NS / 2) clk = ~clk;

    always @(posedge clk) begin
        if (rst == `RstEnable || uart_debug_pin == 1'b1) begin
            sid_uart_write_count <= 0;
        end else if ((u_dut.u_tinyriscv_soc_top.s3_we_o == `WriteEnable) &&
                     (u_dut.u_tinyriscv_soc_top.s3_addr_o[7:0] == 8'h0c)) begin
            $display("[SID_TB] UART_TXDATA write[%0d] = 0x%02x (%c), pc=0x%08x sid_state=%0d sid_index=%0d",
                     sid_uart_write_count,
                     u_dut.u_tinyriscv_soc_top.s3_data_o[7:0],
                     u_dut.u_tinyriscv_soc_top.s3_data_o[7:0],
                     u_dut.u_tinyriscv_soc_top.u_tinyriscv.u_pc_reg.pc_o,
                     u_dut.u_tinyriscv_soc_top.u_tinyriscv.u_ex.sid_state,
                     u_dut.u_tinyriscv_soc_top.u_tinyriscv.u_ex.sid_index);
            sid_uart_write_count <= sid_uart_write_count + 1;
        end
    end

`ifdef TRACE_CORE
    always @(posedge clk) begin
        if ((rst == `RstDisable) && (uart_debug_pin == 1'b0)) begin
            if (u_dut.u_tinyriscv_soc_top.u_tinyriscv.final_reg_we == `WriteEnable) begin
                if ((u_dut.u_tinyriscv_soc_top.u_tinyriscv.ex_reg_waddr_o == 5'd1) ||
                    (u_dut.u_tinyriscv_soc_top.u_tinyriscv.ex_reg_waddr_o == 5'd2) ||
                    (u_dut.u_tinyriscv_soc_top.u_tinyriscv.ex_reg_waddr_o == 5'd8) ||
                    (u_dut.u_tinyriscv_soc_top.u_tinyriscv.ex_reg_waddr_o == 5'd26) ||
                    (u_dut.u_tinyriscv_soc_top.u_tinyriscv.ex_reg_waddr_o == 5'd27)) begin
                    $display("[SID_TRACE] REG x%0d <= 0x%08x pc=0x%08x inst=0x%08x state=%0d ex_we=%b gate=%b",
                             u_dut.u_tinyriscv_soc_top.u_tinyriscv.ex_reg_waddr_o,
                             u_dut.u_tinyriscv_soc_top.u_tinyriscv.ex_reg_wdata_o,
                             u_dut.u_tinyriscv_soc_top.u_tinyriscv.u_pc_reg.pc_o,
                             u_dut.u_tinyriscv_soc_top.u_tinyriscv.ie_inst_o,
                             u_dut.u_tinyriscv_soc_top.u_tinyriscv.ctrl_state_o,
                             u_dut.u_tinyriscv_soc_top.u_tinyriscv.ex_reg_we_o,
                             u_dut.u_tinyriscv_soc_top.u_tinyriscv.reg_we_gate_o);
                end
            end

            if ((u_dut.u_tinyriscv_soc_top.u_tinyriscv.rib_ex_req_o == `RIB_REQ) &&
                (u_dut.u_tinyriscv_soc_top.u_tinyriscv.rib_ex_addr_o[31:28] == 4'h1)) begin
                $display("[SID_TRACE] MEM %s addr=0x%08x wdata=0x%08x rdata=0x%08x ack=%b pc=0x%08x inst=0x%08x state=%0d",
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.rib_ex_we_o ? "WR" : "RD",
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.rib_ex_addr_o,
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.rib_ex_data_o,
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.rib_ex_data_i,
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.rib_ex_ack_i,
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.u_pc_reg.pc_o,
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.ie_inst_o,
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.ctrl_state_o);
            end

            if (u_dut.u_tinyriscv_soc_top.u_tinyriscv.ctrl_jump_flag_o == `JumpEnable) begin
                $display("[SID_TRACE] JUMP to 0x%08x pc=0x%08x inst=0x%08x ra=0x%08x state=%0d",
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.ctrl_jump_addr_o,
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.u_pc_reg.pc_o,
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.ie_inst_o,
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.u_regs.regs[1],
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.ctrl_state_o);
            end

            if ((u_dut.u_tinyriscv_soc_top.u_tinyriscv.ctrl_state_o == 4'd3) &&
                (u_dut.u_tinyriscv_soc_top.u_tinyriscv.ie_inst_addr_o >= 32'h00000180) &&
                (u_dut.u_tinyriscv_soc_top.u_tinyriscv.ie_inst_addr_o <= 32'h000001e4)) begin
                $display("[SID_TRACE] EX pc_ex=0x%08x pc_reg=0x%08x inst=0x%08x raddr=%0d/%0d rdata=0x%08x/0x%08x ex_waddr=%0d ex_wdata=0x%08x final_we=%b sp=0x%08x",
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.ie_inst_addr_o,
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.u_pc_reg.pc_o,
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.ie_inst_o,
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.id_reg1_raddr_o,
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.id_reg2_raddr_o,
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.regs_rdata1_o,
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.regs_rdata2_o,
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.ex_reg_waddr_o,
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.ex_reg_wdata_o,
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.final_reg_we,
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.u_regs.regs[2]);
            end
        end
    end
`endif

    function [7:0] expected_id_byte;
        input integer index;
        begin
            case (index)
                0: expected_id_byte = "2";
                1: expected_id_byte = "0";
                2: expected_id_byte = "2";
                3: expected_id_byte = "5";
                4: expected_id_byte = "2";
                5: expected_id_byte = "1";
                6: expected_id_byte = "0";
                7: expected_id_byte = "9";
                8: expected_id_byte = "0";
                9: expected_id_byte = "5";
                default: expected_id_byte = 8'h00;
            endcase
        end
    endfunction

    initial begin
        inst_file = "Extend_Inst_Example/sID/sID_inst.data";
        vcd_file = "Extend_Inst_Example/sID/build/sID_tb.vcd";
        rom_dump_file = "Extend_Inst_Example/sID/build/downloaded_rom_after_uart.hex";
        if ($value$plusargs("INST_FILE=%s", inst_file)) begin end
        if ($value$plusargs("VCD_FILE=%s", vcd_file)) begin end
        if ($value$plusargs("ROM_DUMP=%s", rom_dump_file)) begin end
    end

    initial begin
        clk = 1'b0;
        rst = `RstEnable;
        uart_debug_pin = 1'b0;
        uart_rx_pin = 1'b1;
        sid_pass = 1;

        load_inst_data;

        repeat (10) @(posedge clk);
        uart_debug_pin = 1'b1;
        rst = `RstDisable;

        repeat (200) @(posedge clk);
        send_first_packet;
        recv_uart_byte(ack, rx_ok);
        check_uart_rx(rx_ok, "packet 0 ACK");
        check_ack(ack, 0);

        for (i = 0; i < total_packets; i = i + 1) begin
            send_data_packet(i);
            recv_uart_byte(ack, rx_ok);
            check_uart_rx(rx_ok, "data packet ACK");
            check_ack(ack, i + 1);
        end

        $display("[SID_TB] UART_DEBUG download finished: %0d words, %0d bytes, %0d data packets",
                 word_count, fw_size, total_packets);

        $writememh(rom_dump_file, u_dut.u_bridge_slave_top.u_rom._rom);
        $display("[SID_TB] ROM image saved to %0s", rom_dump_file);

        uart_debug_pin = 1'b0;
        uart_rx_pin = 1'b1;
        repeat (20) @(posedge clk);

        rst = `RstEnable;
        repeat (20) @(posedge clk);
        rst = `RstDisable;

        wait_uart_idle_high;
        $display("[SID_TB] CPU released, waiting for sID UART output...");

        for (i = 0; i < SID_LEN; i = i + 1) begin
            recv_uart_byte(rx_byte, rx_ok);
            check_uart_rx(rx_ok, "sID UART byte");
            sid_rx[i] = rx_byte;
            $display("[SID_TB] sID UART byte[%0d] = 0x%02x (%c)", i, rx_byte, rx_byte);
        end

        $write("[SID_TB] Captured sID string: ");
        for (i = 0; i < SID_LEN; i = i + 1) begin
            $write("%c", sid_rx[i]);
        end
        $write("\n");
        $display("[SID_TB] Expected sID string: %0s", EXPECTED_ID_TEXT);

        for (i = 0; i < SID_LEN; i = i + 1) begin
            if (sid_rx[i] !== expected_id_byte(i)) begin
                sid_pass = 0;
                $display("[SID_TB] ERROR: byte[%0d] expected 0x%02x (%c), got 0x%02x (%c)",
                         i, expected_id_byte(i), expected_id_byte(i), sid_rx[i], sid_rx[i]);
            end
        end

        wait_for_program_done;

        if (sid_pass) begin
            $display("[SID_TB] FINAL PASS: sID UART output matches %0s, x26(s10)=0x%08x",
                     EXPECTED_ID_TEXT, u_dut.u_tinyriscv_soc_top.u_tinyriscv.u_regs.regs[26]);
        end else begin
            $display("[SID_TB] FINAL FAIL: sID UART output mismatch");
            $finish;
        end

        repeat (200) @(posedge clk);
        $finish;
    end

    initial begin
`ifndef NO_DUMP
        #1;
        $dumpfile(vcd_file);
        $dumpvars(0, sID_tb);
`endif
    end

    initial begin
`ifdef FAST_UART_SIM
        #100000000;
`elsif IVERILOG_FAST_SIM
        #100000000;
`else
        #2000000000;
`endif
        $display("[SID_TB] TIMEOUT: x26=0x%08x x27=0x%08x pc=0x%08x succ=%b",
                 u_dut.u_tinyriscv_soc_top.u_tinyriscv.u_regs.regs[26],
                 u_dut.u_tinyriscv_soc_top.u_tinyriscv.u_regs.regs[27],
                 u_dut.u_tinyriscv_soc_top.u_tinyriscv.u_pc_reg.pc_o,
                 succ);
        $finish;
    end

    task load_inst_data;
        begin
            word_count = 0;
            fd = $fopen(inst_file, "r");
            if (fd == 0) begin
                $display("[SID_TB] ERROR: cannot open %0s", inst_file);
                $finish;
            end

            code = $fscanf(fd, "%h", word_tmp);
            while (code == 1) begin
                if (code == 1) begin
                    if (word_count >= MAX_WORDS) begin
                        $display("[SID_TB] ERROR: firmware too large");
                        $finish;
                    end
                    inst_words[word_count] = word_tmp;
                    fw_bytes[word_count * 4 + 0] = word_tmp[7:0];
                    fw_bytes[word_count * 4 + 1] = word_tmp[15:8];
                    fw_bytes[word_count * 4 + 2] = word_tmp[23:16];
                    fw_bytes[word_count * 4 + 3] = word_tmp[31:24];
                    word_count = word_count + 1;
                end
                code = $fscanf(fd, "%h", word_tmp);
            end
            $fclose(fd);

            fw_size = word_count * 4;
            total_packets = (fw_size / PAYLOAD_LEN) + 1;
            $display("[SID_TB] Loaded %0s: %0d words, %0d bytes, %0d data packets",
                     inst_file, word_count, fw_size, total_packets);
        end
    endtask

    task clear_packet;
        integer n;
        begin
            for (n = 0; n < PACKET_LEN; n = n + 1) begin
                packet[n] = 8'h00;
            end
        end
    endtask

    task calc_packet_crc;
        output [15:0] crc_o;
        integer pos;
        integer bit_idx;
        reg [15:0] crc_r;
        begin
            crc_r = 16'hffff;
            for (pos = 1; pos <= PAYLOAD_LEN; pos = pos + 1) begin
                crc_r = crc_r ^ packet[pos];
                for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                    if (crc_r[0] == 1'b1) begin
                        crc_r = (crc_r >> 1) ^ 16'ha001;
                    end else begin
                        crc_r = crc_r >> 1;
                    end
                end
            end
            crc_o = crc_r;
        end
    endtask

    task send_first_packet;
        begin
            clear_packet;
            packet[0] = 8'h00;

            packet[1]  = "s";
            packet[2]  = "I";
            packet[3]  = "D";
            packet[4]  = "_";
            packet[5]  = "i";
            packet[6]  = "n";
            packet[7]  = "s";
            packet[8]  = "t";
            packet[9]  = ".";
            packet[10] = "d";
            packet[11] = "a";
            packet[12] = "t";
            packet[13] = "a";

            packet[25] = fw_size[31:24];
            packet[26] = fw_size[23:16];
            packet[27] = fw_size[15:8];
            packet[28] = fw_size[7:0];

            calc_packet_crc(crc);
            packet[PACKET_LEN - 2] = crc[7:0];
            packet[PACKET_LEN - 1] = crc[15:8];

            $display("[SID_TB] Send packet #0, file size = %0d", fw_size);
            send_packet;
        end
    endtask

    task send_data_packet;
        input integer packet_index;
        integer n;
        integer byte_index;
        begin
            clear_packet;
            packet[0] = packet_index + 1;

            for (n = 0; n < PAYLOAD_LEN; n = n + 1) begin
                byte_index = packet_index * PAYLOAD_LEN + n;
                if (byte_index < fw_size) begin
                    packet[n + 1] = fw_bytes[byte_index];
                end
            end

            calc_packet_crc(crc);
            packet[PACKET_LEN - 2] = crc[7:0];
            packet[PACKET_LEN - 1] = crc[15:8];

            $display("[SID_TB] Send packet #%0d", packet_index + 1);
            send_packet;
        end
    endtask

    task send_packet;
        integer n;
        begin
            for (n = 0; n < PACKET_LEN; n = n + 1) begin
                send_uart_byte(packet[n]);
            end
        end
    endtask

    task send_uart_byte;
        input [7:0] data;
        integer bit_idx;
        begin
            uart_rx_pin = 1'b0;
            #(UART_BIT_NS);

            for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                uart_rx_pin = data[bit_idx];
                #(UART_BIT_NS);
            end

            uart_rx_pin = 1'b1;
            #(UART_BIT_NS);
        end
    endtask

    task recv_uart_byte;
        output [7:0] data;
        output ok;
        integer bit_idx;
        integer cycles;
        reg prev_tx;
        begin
            data = 8'h00;
            ok = 1'b0;

            prev_tx = uart_tx_pin;
            begin: wait_start_edge
                for (cycles = 0; cycles < UART_START_TIMEOUT_CYCLES; cycles = cycles + 1) begin
                    @(posedge clk);
                    if ((prev_tx === 1'b1) && (uart_tx_pin === 1'b0)) begin
                        ok = 1'b1;
                        disable wait_start_edge;
                    end
                    prev_tx = uart_tx_pin;
                end
            end

            if (ok) begin
                #(UART_BIT_NS + (UART_BIT_NS / 2));
                for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                    data[bit_idx] = uart_tx_pin;
                    #(UART_BIT_NS);
                end
            end
        end
    endtask

    task check_uart_rx;
        input ok_i;
        input [255:0] ctx;
        begin
            if (!ok_i) begin
                $display("[SID_TB] ERROR: UART receive timeout while waiting for %0s", ctx);
                $display("[SID_TB] DEBUG: pc=0x%08x ctrl_state=0x%0x inst_ex=0x%08x x26=0x%08x x27=0x%08x succ=%b",
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.u_pc_reg.pc_o,
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.ctrl_state_o,
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.ie_inst_o,
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.u_regs.regs[26],
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.u_regs.regs[27],
                         succ);
                $display("[SID_TB] DEBUG: sid_state=%0d sid_index=%0d ext_start=%b ext_done=%b mem_req=%b mem_we=%b mem_addr=0x%08x mem_wdata=0x%08x mem_rdata=0x%08x",
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.u_ex.sid_state,
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.u_ex.sid_index,
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.ext_inst_start_o,
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.ext_inst_done_o,
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.ex_mem_req_o,
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.ex_mem_we_o,
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.rib_ex_addr_o,
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.ex_mem_wdata_o,
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.ex_mem_rdata_in);
                $display("[SID_TB] DEBUG: uart_ctrl=0x%08x uart_status=0x%08x uart_state=0x%0x uart_tx=%b",
                         u_dut.u_tinyriscv_soc_top.uart_0.uart_ctrl,
                         u_dut.u_tinyriscv_soc_top.uart_0.uart_status,
                         u_dut.u_tinyriscv_soc_top.uart_0.state,
                         uart_tx_pin);
                $finish;
            end
        end
    endtask

    task check_ack;
        input [7:0] ack_i;
        input integer packet_no;
        begin
            if (ack_i !== 8'h06) begin
                $display("[SID_TB] ERROR: packet #%0d ACK failed, rx = 0x%02x", packet_no, ack_i);
                $finish;
            end
            $display("[SID_TB] Packet #%0d ACK OK", packet_no);
        end
    endtask

    task wait_uart_idle_high;
        begin
            while (uart_tx_pin !== 1'b1) begin
                @(posedge clk);
            end
            repeat (20) @(posedge clk);
        end
    endtask

    task wait_for_program_done;
        begin
            wait_cycles = 0;
            while ((u_dut.u_tinyriscv_soc_top.u_tinyriscv.u_regs.regs[26] !== 32'h00000001) &&
                   (wait_cycles < 1000000)) begin
                wait_cycles = wait_cycles + 1;
                @(posedge clk);
            end

            if (u_dut.u_tinyriscv_soc_top.u_tinyriscv.u_regs.regs[26] !== 32'h00000001) begin
                $display("[SID_TB] ERROR: program did not reach success loop, x26=0x%08x x27=0x%08x pc=0x%08x",
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.u_regs.regs[26],
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.u_regs.regs[27],
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.u_pc_reg.pc_o);
                $display("[SID_TB] DEBUG: ram[14]=0x%08x ram[15]=0x%08x ra(x1)=0x%08x sp(x2)=0x%08x s0(x8)=0x%08x",
                         u_dut.u_bridge_slave_top.u_ram._ram[14],
                         u_dut.u_bridge_slave_top.u_ram._ram[15],
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.u_regs.regs[1],
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.u_regs.regs[2],
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.u_regs.regs[8]);
                $finish;
            end
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
