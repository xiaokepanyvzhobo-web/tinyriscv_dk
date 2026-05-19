`timescale 1ns/1ps

`include "defines.v"

module Temp_tb;

    localparam integer CLK_PERIOD_NS = 20;
`ifdef FAST_UART_SIM
    localparam integer UART_BIT_NS = 180;
`elsif IVERILOG_FAST_SIM
    localparam integer UART_BIT_NS = 180;
`else
    localparam integer UART_BIT_NS = 8820;
`endif

    localparam integer PACKET_LEN = 35;
    localparam integer PAYLOAD_LEN = 32;
    localparam integer MAX_WORDS = 4096;
    localparam integer MAX_BYTES = MAX_WORDS * 4;
    localparam integer TEMP_LEN = 1;
    localparam integer UART_START_TIMEOUT_CYCLES = 200000;
    localparam [15:0] LM75_TEMP_REG_VALUE = 16'h1900;
    localparam [7:0] EXPECTED_TEMP_BYTE = 8'h32;

    reg clk;
    reg rst;
    reg uart_debug_pin;
    reg uart_rx_pin;

    wire succ;
    wire uart_tx_pin;
    tri1 io_sda;
    wire io_scl;
    wire slave_sda_o;
    wire slave_sda_oe;

    reg [31:0] inst_words [0:MAX_WORDS - 1];
    reg [7:0] fw_bytes [0:MAX_BYTES - 1];
    reg [7:0] packet [0:PACKET_LEN - 1];
    reg [7:0] temp_rx [0:TEMP_LEN - 1];

    reg [8*256-1:0] inst_file;
    reg [8*256-1:0] rom_dump_file;

    integer fd;
    integer code;
    integer word_count;
    integer fw_size;
    integer total_packets;
    integer i;
    integer wait_cycles;
    integer temp_pass;
    integer temp_uart_write_count;
    reg [31:0] last_valid_pc;
    reg [31:0] last_valid_inst;
    reg [3:0] last_valid_ctrl_state;
    reg [4:0] last_iic_cs;
    reg [3:0] last_slave_state;
    reg [31:0] word_tmp;
    reg [15:0] crc;
    reg [7:0] ack;
    reg [7:0] rx_byte;
    reg rx_ok;

    always #(CLK_PERIOD_NS / 2) clk = ~clk;

    always @(posedge clk) begin
        if (rst == `RstEnable) begin
            last_valid_pc <= `ZeroWord;
            last_valid_inst <= `INST_NOP;
            last_valid_ctrl_state <= 4'h0;
        end else if (^u_dut.u_tinyriscv_soc_top.u_tinyriscv.pc_pc_o !== 1'bx) begin
            last_valid_pc <= u_dut.u_tinyriscv_soc_top.u_tinyriscv.pc_pc_o;
            last_valid_inst <= u_dut.u_tinyriscv_soc_top.u_tinyriscv.ie_inst_o;
            last_valid_ctrl_state <= u_dut.u_tinyriscv_soc_top.u_tinyriscv.ctrl_state_o;
        end
    end

    always @(posedge clk) begin
        if ((rst == `RstEnable) || (uart_debug_pin == 1'b1)) begin
            temp_uart_write_count <= 0;
        end else if ((u_dut.u_tinyriscv_soc_top.s3_we_o == `WriteEnable) &&
                     (u_dut.u_tinyriscv_soc_top.s3_addr_o[7:0] == 8'h0c)) begin
            $display("[TEMP_TB] UART_TXDATA write[%0d] = 0x%02x, pc=0x%08x",
                     temp_uart_write_count,
                     u_dut.u_tinyriscv_soc_top.s3_data_o[7:0],
                     u_dut.u_tinyriscv_soc_top.u_tinyriscv.pc_pc_o);
            temp_uart_write_count <= temp_uart_write_count + 1;
        end
    end

    always @(posedge clk) begin
        if ((rst == `RstDisable) && (uart_debug_pin == 1'b0) &&
            (u_dut.u_tinyriscv_soc_top.u_tinyriscv.final_reg_we == `WriteEnable) &&
            (u_dut.u_tinyriscv_soc_top.u_tinyriscv.ex_reg_waddr_o == 5'd1)) begin
            $display("[TEMP_TB] RA_WRITE: pc=0x%08x inst_ex=0x%08x ra<=0x%08x ctrl_state=0x%0x",
                     u_dut.u_tinyriscv_soc_top.u_tinyriscv.pc_pc_o,
                     u_dut.u_tinyriscv_soc_top.u_tinyriscv.ie_inst_o,
                     u_dut.u_tinyriscv_soc_top.u_tinyriscv.ex_reg_wdata_o,
                     u_dut.u_tinyriscv_soc_top.u_tinyriscv.ctrl_state_o);
        end
    end

    always @(posedge clk) begin
        if ((rst == `RstDisable) && (uart_debug_pin == 1'b0) &&
            (u_dut.u_tinyriscv_soc_top.u_tinyriscv.final_reg_we == `WriteEnable) &&
            (u_dut.u_tinyriscv_soc_top.u_tinyriscv.ex_reg_waddr_o == 5'd2)) begin
            $display("[TEMP_TB] SP_WRITE: pc=0x%08x inst_ex=0x%08x sp<=0x%08x ctrl_state=0x%0x",
                     u_dut.u_tinyriscv_soc_top.u_tinyriscv.pc_pc_o,
                     u_dut.u_tinyriscv_soc_top.u_tinyriscv.ie_inst_o,
                     u_dut.u_tinyriscv_soc_top.u_tinyriscv.ex_reg_wdata_o,
                     u_dut.u_tinyriscv_soc_top.u_tinyriscv.ctrl_state_o);
        end
    end

    always @(posedge clk) begin
        if ((rst == `RstDisable) && (uart_debug_pin == 1'b0) &&
            (u_dut.u_tinyriscv_soc_top.u_tinyriscv.final_reg_we == `WriteEnable) &&
            ((u_dut.u_tinyriscv_soc_top.u_tinyriscv.ex_reg_waddr_o == 5'd10) ||
             (u_dut.u_tinyriscv_soc_top.u_tinyriscv.ex_reg_waddr_o == 5'd15) ||
             (u_dut.u_tinyriscv_soc_top.u_tinyriscv.ex_reg_waddr_o == 5'd26))) begin
            $display("[TEMP_TB] REG_WRITE: pc=0x%08x inst_ex=0x%08x x%0d<=0x%08x ctrl_state=0x%0x",
                     u_dut.u_tinyriscv_soc_top.u_tinyriscv.pc_pc_o,
                     u_dut.u_tinyriscv_soc_top.u_tinyriscv.ie_inst_o,
                     u_dut.u_tinyriscv_soc_top.u_tinyriscv.ex_reg_waddr_o,
                     u_dut.u_tinyriscv_soc_top.u_tinyriscv.ex_reg_wdata_o,
                     u_dut.u_tinyriscv_soc_top.u_tinyriscv.ctrl_state_o);
        end
    end

    always @(posedge clk) begin
        if ((rst == `RstDisable) && (uart_debug_pin == 1'b0) &&
            (u_dut.u_tinyriscv_soc_top.u_tinyriscv.rib_ex_req_o == `RIB_REQ) &&
            (u_dut.u_tinyriscv_soc_top.u_tinyriscv.rib_ex_we_o == `WriteDisable)) begin
            $display("[TEMP_TB] LOAD_REQ: pc=0x%08x inst_ex=0x%08x addr=0x%08x data_i=0x%08x ack=%b ctrl_state=0x%0x",
                     u_dut.u_tinyriscv_soc_top.u_tinyriscv.pc_pc_o,
                     u_dut.u_tinyriscv_soc_top.u_tinyriscv.ie_inst_o,
                     u_dut.u_tinyriscv_soc_top.u_tinyriscv.rib_ex_addr_o,
                     u_dut.u_tinyriscv_soc_top.u_tinyriscv.rib_ex_data_i,
                     u_dut.u_tinyriscv_soc_top.u_tinyriscv.rib_ex_ack_i,
                     u_dut.u_tinyriscv_soc_top.u_tinyriscv.ctrl_state_o);
        end
    end

    always @(posedge clk) begin
        if ((rst == `RstDisable) && (uart_debug_pin == 1'b0) &&
            (u_dut.u_tinyriscv_soc_top.u_tinyriscv.rib_ex_req_o == `RIB_REQ) &&
            (u_dut.u_tinyriscv_soc_top.u_tinyriscv.rib_ex_we_o == `WriteEnable)) begin
            $display("[TEMP_TB] STORE_REQ: pc=0x%08x inst_ex=0x%08x addr=0x%08x data=0x%08x ack=%b ctrl_state=0x%0x",
                     u_dut.u_tinyriscv_soc_top.u_tinyriscv.pc_pc_o,
                     u_dut.u_tinyriscv_soc_top.u_tinyriscv.ie_inst_o,
                     u_dut.u_tinyriscv_soc_top.u_tinyriscv.rib_ex_addr_o,
                     u_dut.u_tinyriscv_soc_top.u_tinyriscv.rib_ex_data_o,
                     u_dut.u_tinyriscv_soc_top.u_tinyriscv.rib_ex_ack_i,
                     u_dut.u_tinyriscv_soc_top.u_tinyriscv.ctrl_state_o);
        end
    end

    always @(posedge clk) begin
        if (u_dut.u_bridge_slave_top.u_ram.we_i == `WriteEnable) begin
            $display("[TEMP_TB] RAM_WRITE: addr=0x%08x word_index=0x%08x data=0x%08x",
                     u_dut.u_bridge_slave_top.u_ram.addr_i,
                     u_dut.u_bridge_slave_top.u_ram.addr_i[31:2],
                     u_dut.u_bridge_slave_top.u_ram.data_i);
        end
    end

    always @(posedge clk) begin
        if ((rst == `RstDisable) && (uart_debug_pin == 1'b0)) begin
            if (u_dut.u_tinyriscv_soc_top.u_iic_dk.iic_cs !== last_iic_cs) begin
                $display("[TEMP_TB] IIC_STATE: %0d -> %0d, sda_cnt=%0d scl=%b sda=%b oe=%b rx_ack=%b data=0x%04x",
                         last_iic_cs,
                         u_dut.u_tinyriscv_soc_top.u_iic_dk.iic_cs,
                         u_dut.u_tinyriscv_soc_top.u_iic_dk.sda_counter,
                         io_scl,
                         io_sda,
                         u_dut.u_tinyriscv_soc_top.u_iic_dk.SDA_oe_o,
                         u_dut.u_tinyriscv_soc_top.u_iic_dk.rx_ack,
                         u_dut.u_tinyriscv_soc_top.u_iic_dk.data_out_reg[15:0]);
                last_iic_cs <= u_dut.u_tinyriscv_soc_top.u_iic_dk.iic_cs;
            end

            if (u_lm75_slave.state !== last_slave_state) begin
                $display("[TEMP_TB] LM75_STATE: %0d -> %0d, bit=%0d rw=%b shift=0x%02x sda_oe=%b",
                         last_slave_state,
                         u_lm75_slave.state,
                         u_lm75_slave.bit_cnt,
                         u_lm75_slave.rw_flag,
                         u_lm75_slave.shift_reg,
                         u_lm75_slave.sda_oe);
                last_slave_state <= u_lm75_slave.state;
            end
        end
    end

    initial begin
        inst_file = "liudk_test/temp_test/Temp.data";
        rom_dump_file = "liudk_test/temp_test/build/downloaded_rom_after_uart.hex";
        if ($value$plusargs("INST_FILE=%s", inst_file)) begin end
        if ($value$plusargs("ROM_DUMP=%s", rom_dump_file)) begin end
    end

    initial begin
        clk = 1'b0;
        rst = `RstEnable;
        uart_debug_pin = 1'b0;
        uart_rx_pin = 1'b1;
        temp_pass = 1;
        last_iic_cs = 5'h1f;
        last_slave_state = 4'hf;

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

        $display("[TEMP_TB] UART_DEBUG download finished: %0d words, %0d bytes, %0d data packets",
                 word_count, fw_size, total_packets);
        $writememh(rom_dump_file, u_dut.u_bridge_slave_top.u_rom._rom);
        $display("[TEMP_TB] ROM image saved to %0s", rom_dump_file);

        uart_debug_pin = 1'b0;
        uart_rx_pin = 1'b1;
        repeat (20) @(posedge clk);

        rst = `RstEnable;
        repeat (20) @(posedge clk);
        rst = `RstDisable;

        wait_uart_idle_high;
        $display("[TEMP_TB] CPU released, waiting for TEMP UART output...");

        for (i = 0; i < TEMP_LEN; i = i + 1) begin
            recv_uart_byte(rx_byte, rx_ok);
            check_uart_rx(rx_ok, "TEMP UART byte");
            temp_rx[i] = rx_byte;
            $display("[TEMP_TB] TEMP UART byte[%0d] = 0x%02x", i, rx_byte);
        end

        $display("[TEMP_TB] Captured TEMP byte: 0x%02x", temp_rx[0]);
        $display("[TEMP_TB] Expected TEMP byte: 0x%02x", EXPECTED_TEMP_BYTE);

        if (temp_rx[0] !== EXPECTED_TEMP_BYTE) begin
            temp_pass = 0;
            $display("[TEMP_TB] ERROR: expected UART byte 0x%02x, got 0x%02x",
                     EXPECTED_TEMP_BYTE, temp_rx[0]);
        end

        wait_for_program_done;

        if (temp_pass) begin
            $display("[TEMP_TB] FINAL PASS: UART output is 0x%02x, x26(s10)=0x%08x",
                     temp_rx[0], u_dut.u_tinyriscv_soc_top.u_tinyriscv.u_regs.regs[26]);
        end else begin
            $display("[TEMP_TB] FINAL FAIL");
            dump_ram_contents;
            $finish;
        end

        repeat (200) @(posedge clk);
        dump_ram_contents;
        $finish;
    end

    initial begin
`ifndef NO_DUMP
`ifdef FSDB
        $fsdbDumpfile("liudk_test/temp_test/build/Temp_tb.fsdb");
        $fsdbDumpvars(0, Temp_tb);
        $fsdbDumpMDA(0, Temp_tb);
`else
        $dumpfile("liudk_test/temp_test/build/Temp_tb.vcd");
        $dumpvars(0, Temp_tb);
`endif
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
        $display("[TEMP_TB] TIMEOUT: x10=0x%08x x15=0x%08x x26=0x%08x pc=0x%08x succ=%b",
                 u_dut.u_tinyriscv_soc_top.u_tinyriscv.u_regs.regs[10],
                 u_dut.u_tinyriscv_soc_top.u_tinyriscv.u_regs.regs[15],
                 u_dut.u_tinyriscv_soc_top.u_tinyriscv.u_regs.regs[26],
                 u_dut.u_tinyriscv_soc_top.u_tinyriscv.pc_pc_o,
                 succ);
        $display("[TEMP_TB] LAST_VALID: pc=0x%08x inst_ex=0x%08x ctrl_state=0x%0x",
                 last_valid_pc, last_valid_inst, last_valid_ctrl_state);
        dump_ram_contents;
        $finish;
    end

    task load_inst_data;
        begin
            word_count = 0;
            fd = $fopen(inst_file, "r");
            if (fd == 0) begin
                $display("[TEMP_TB] ERROR: cannot open %0s", inst_file);
                $finish;
            end

            code = $fscanf(fd, "%h", word_tmp);
            while (code == 1) begin
                if (word_count >= MAX_WORDS) begin
                    $display("[TEMP_TB] ERROR: firmware too large");
                    $finish;
                end
                inst_words[word_count] = word_tmp;
                fw_bytes[word_count * 4 + 0] = word_tmp[7:0];
                fw_bytes[word_count * 4 + 1] = word_tmp[15:8];
                fw_bytes[word_count * 4 + 2] = word_tmp[23:16];
                fw_bytes[word_count * 4 + 3] = word_tmp[31:24];
                word_count = word_count + 1;
                code = $fscanf(fd, "%h", word_tmp);
            end
            $fclose(fd);

            fw_size = word_count * 4;
            total_packets = (fw_size / PAYLOAD_LEN) + ((fw_size % PAYLOAD_LEN) ? 1 : 0);
            $display("[TEMP_TB] Loaded %0s: %0d words, %0d bytes, %0d data packets",
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
            packet[1]  = "T";
            packet[2]  = "e";
            packet[3]  = "m";
            packet[4]  = "p";
            packet[5]  = ".";
            packet[6]  = "d";
            packet[7]  = "a";
            packet[8]  = "t";
            packet[9]  = "a";
            packet[25] = fw_size[31:24];
            packet[26] = fw_size[23:16];
            packet[27] = fw_size[15:8];
            packet[28] = fw_size[7:0];
            calc_packet_crc(crc);
            packet[PACKET_LEN - 2] = crc[7:0];
            packet[PACKET_LEN - 1] = crc[15:8];
            $display("[TEMP_TB] Send packet #0, file size = %0d", fw_size);
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
            $display("[TEMP_TB] Send packet #%0d", packet_index + 1);
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
                $display("[TEMP_TB] ERROR: UART receive timeout while waiting for %0s", ctx);
                $display("[TEMP_TB] DEBUG: pc=0x%08x ctrl_state=0x%0x inst_ex=0x%08x x10=0x%08x x15=0x%08x succ=%b",
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.pc_pc_o,
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.ctrl_state_o,
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.ie_inst_o,
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.u_regs.regs[10],
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.u_regs.regs[15],
                         succ);
                $display("[TEMP_TB] LAST_VALID: pc=0x%08x inst_ex=0x%08x ctrl_state=0x%0x",
                         last_valid_pc, last_valid_inst, last_valid_ctrl_state);
                dump_ram_contents;
                $finish;
            end
        end
    endtask

    task check_ack;
        input [7:0] ack_i;
        input integer packet_no;
        begin
            if (ack_i !== 8'h06) begin
                $display("[TEMP_TB] ERROR: packet #%0d ACK failed, rx = 0x%02x", packet_no, ack_i);
                $finish;
            end
            $display("[TEMP_TB] Packet #%0d ACK OK", packet_no);
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
                $display("[TEMP_TB] ERROR: program did not reach success loop, x26=0x%08x x27=0x%08x pc=0x%08x",
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.u_regs.regs[26],
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.u_regs.regs[27],
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.pc_pc_o);
                $display("[TEMP_TB] LAST_VALID: pc=0x%08x inst_ex=0x%08x ctrl_state=0x%0x",
                         last_valid_pc, last_valid_inst, last_valid_ctrl_state);
                dump_ram_contents;
                $finish;
            end
        end
    endtask

    task dump_ram_contents;
        integer ram_i;
        begin
            $display("[TEMP_TB] RAM_DUMP_BEGIN");
            for (ram_i = 0; ram_i < `MemNum; ram_i = ram_i + 1) begin
                $display("[TEMP_TB] RAM[%0d] = 0x%08x", ram_i, u_dut.u_bridge_slave_top.u_ram._ram[ram_i]);
            end
            $display("[TEMP_TB] RAM_DUMP_END");
        end
    endtask

    assign io_sda = slave_sda_oe ? (slave_sda_o ? 1'bz : 1'b0) : 1'bz;

    lm75_slave_model #(
        .TEMP_REG_VALUE(LM75_TEMP_REG_VALUE)
    ) u_lm75_slave (
        .sys_clk (clk),
        .rst_n   (rst),
        .hw_addr (3'b001),
        .scl_i   (io_scl),
        .sda_i   (io_sda),
        .sda_o   (slave_sda_o),
        .sda_oe  (slave_sda_oe)
    );

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
