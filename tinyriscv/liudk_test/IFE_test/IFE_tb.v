`timescale 1ns/1ps

`include "defines.v"

module IFE_tb;

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
    localparam integer IFE_LEN = 1;
    localparam integer UART_START_TIMEOUT_CYCLES = 200000;
    localparam [7:0] EXPECTED_IFE_BYTE = 8'h8a;

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
    reg [7:0] ife_rx [0:IFE_LEN - 1];

    reg [8*256-1:0] inst_file;
    reg [8*256-1:0] rom_dump_file;

    integer fd;
    integer code;
    integer word_count;
    integer fw_size;
    integer total_packets;
    integer i;
    integer wait_cycles;
    integer ife_pass;
    integer ife_uart_write_count;
    reg [31:0] last_valid_pc;
    reg [31:0] last_valid_inst;
    reg [3:0] last_valid_ctrl_state;
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
            ife_uart_write_count <= 0;
        end else if ((u_dut.u_tinyriscv_soc_top.s3_we_o == `WriteEnable) &&
                     (u_dut.u_tinyriscv_soc_top.s3_addr_o[7:0] == 8'h0c)) begin
            $display("[IFE_TB] UART_TXDATA write[%0d] = 0x%02x, pc=0x%08x",
                     ife_uart_write_count,
                     u_dut.u_tinyriscv_soc_top.s3_data_o[7:0],
                     u_dut.u_tinyriscv_soc_top.u_tinyriscv.pc_pc_o);
            ife_uart_write_count <= ife_uart_write_count + 1;
        end
    end

    always @(posedge clk) begin
        if ((rst == `RstDisable) && (uart_debug_pin == 1'b0) &&
            (u_dut.u_tinyriscv_soc_top.u_tinyriscv.final_reg_we == `WriteEnable) &&
            (u_dut.u_tinyriscv_soc_top.u_tinyriscv.ex_reg_waddr_o == 5'd1)) begin
            $display("[IFE_TB] RA_WRITE: pc=0x%08x inst_ex=0x%08x ra<=0x%08x ctrl_state=0x%0x",
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
            $display("[IFE_TB] SP_WRITE: pc=0x%08x inst_ex=0x%08x sp<=0x%08x ctrl_state=0x%0x",
                     u_dut.u_tinyriscv_soc_top.u_tinyriscv.pc_pc_o,
                     u_dut.u_tinyriscv_soc_top.u_tinyriscv.ie_inst_o,
                     u_dut.u_tinyriscv_soc_top.u_tinyriscv.ex_reg_wdata_o,
                     u_dut.u_tinyriscv_soc_top.u_tinyriscv.ctrl_state_o);
        end
    end

    always @(posedge clk) begin
        if ((rst == `RstDisable) && (uart_debug_pin == 1'b0) &&
            (u_dut.u_tinyriscv_soc_top.u_tinyriscv.final_reg_we == `WriteEnable) &&
            ((u_dut.u_tinyriscv_soc_top.u_tinyriscv.ex_reg_waddr_o == 5'd30) ||
             (u_dut.u_tinyriscv_soc_top.u_tinyriscv.ex_reg_waddr_o == 5'd31))) begin
            $display("[IFE_TB] REG_WRITE: pc=0x%08x inst_ex=0x%08x x%0d<=0x%08x ctrl_state=0x%0x",
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
            $display("[IFE_TB] LOAD_REQ: pc=0x%08x inst_ex=0x%08x addr=0x%08x data_i=0x%08x ack=%b ctrl_state=0x%0x",
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
            $display("[IFE_TB] STORE_REQ: pc=0x%08x inst_ex=0x%08x addr=0x%08x data=0x%08x ack=%b ctrl_state=0x%0x",
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
            $display("[IFE_TB] RAM_WRITE: addr=0x%08x word_index=0x%08x data=0x%08x",
                     u_dut.u_bridge_slave_top.u_ram.addr_i,
                     u_dut.u_bridge_slave_top.u_ram.addr_i[31:2],
                     u_dut.u_bridge_slave_top.u_ram.data_i);
        end
    end

    initial begin
        inst_file = "liudk_test/IFE_test/IF_inst.data";
        rom_dump_file = "liudk_test/IFE_test/build/downloaded_rom_after_uart.hex";
        if ($value$plusargs("INST_FILE=%s", inst_file)) begin end
        if ($value$plusargs("ROM_DUMP=%s", rom_dump_file)) begin end
    end

    initial begin
        clk = 1'b0;
        rst = `RstEnable;
        uart_debug_pin = 1'b0;
        uart_rx_pin = 1'b1;
        ife_pass = 1;

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

        $display("[IFE_TB] UART_DEBUG download finished: %0d words, %0d bytes, %0d data packets",
                 word_count, fw_size, total_packets);
        $writememh(rom_dump_file, u_dut.u_bridge_slave_top.u_rom._rom);
        $display("[IFE_TB] ROM image saved to %0s", rom_dump_file);

        uart_debug_pin = 1'b0;
        uart_rx_pin = 1'b1;
        repeat (20) @(posedge clk);

        rst = `RstEnable;
        repeat (20) @(posedge clk);
        rst = `RstDisable;

        wait_uart_idle_high;
        $display("[IFE_TB] CPU released, waiting for IFE UART output...");

        for (i = 0; i < IFE_LEN; i = i + 1) begin
            recv_uart_byte(rx_byte, rx_ok);
            check_uart_rx(rx_ok, "IFE UART byte");
            ife_rx[i] = rx_byte;
            $display("[IFE_TB] IFE UART byte[%0d] = 0x%02x", i, rx_byte);
        end

        $display("[IFE_TB] Captured IFE byte: 0x%02x", ife_rx[0]);
        $display("[IFE_TB] Expected IFE byte: 0x%02x", EXPECTED_IFE_BYTE);

        if (ife_rx[0] !== EXPECTED_IFE_BYTE) begin
            ife_pass = 0;
            $display("[IFE_TB] ERROR: expected UART byte 0x%02x, got 0x%02x",
                     EXPECTED_IFE_BYTE, ife_rx[0]);
        end

        repeat (300) @(posedge clk);

        if (u_dut.u_tinyriscv_soc_top.u_tinyriscv.u_regs.regs[30] !== `ZeroWord) begin
            ife_pass = 0;
            $display("[IFE_TB] ERROR: x30(Vmem) expected 0x00000000, got 0x%08x",
                     u_dut.u_tinyriscv_soc_top.u_tinyriscv.u_regs.regs[30]);
        end

        if (ife_pass) begin
            $display("[IFE_TB] FINAL PASS: UART output is 0x%02x and x30(Vmem)=0x%08x",
                     ife_rx[0], u_dut.u_tinyriscv_soc_top.u_tinyriscv.u_regs.regs[30]);
        end else begin
            $display("[IFE_TB] FINAL FAIL");
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
        $fsdbDumpfile("liudk_test/IFE_test/build/IFE_tb.fsdb");
        $fsdbDumpvars(0, IFE_tb);
        $fsdbDumpMDA(0, IFE_tb);
`else
        $dumpfile("liudk_test/IFE_test/build/IFE_tb.vcd");
        $dumpvars(0, IFE_tb);
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
        $display("[IFE_TB] TIMEOUT: x30=0x%08x x31=0x%08x pc=0x%08x succ=%b",
                 u_dut.u_tinyriscv_soc_top.u_tinyriscv.u_regs.regs[30],
                 u_dut.u_tinyriscv_soc_top.u_tinyriscv.u_regs.regs[31],
                 u_dut.u_tinyriscv_soc_top.u_tinyriscv.pc_pc_o,
                 succ);
        $display("[IFE_TB] LAST_VALID: pc=0x%08x inst_ex=0x%08x ctrl_state=0x%0x",
                 last_valid_pc, last_valid_inst, last_valid_ctrl_state);
        dump_ram_contents;
        $finish;
    end

    task load_inst_data;
        begin
            word_count = 0;
            fd = $fopen(inst_file, "r");
            if (fd == 0) begin
                $display("[IFE_TB] ERROR: cannot open %0s", inst_file);
                $finish;
            end

            code = $fscanf(fd, "%h", word_tmp);
            while (code == 1) begin
                if (word_count >= MAX_WORDS) begin
                    $display("[IFE_TB] ERROR: firmware too large");
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
            $display("[IFE_TB] Loaded %0s: %0d words, %0d bytes, %0d data packets",
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
            packet[1]  = "I";
            packet[2]  = "F";
            packet[3]  = "_";
            packet[4]  = "i";
            packet[5]  = "n";
            packet[6]  = "s";
            packet[7]  = "t";
            packet[8]  = ".";
            packet[9]  = "d";
            packet[10] = "a";
            packet[11] = "t";
            packet[12] = "a";
            packet[25] = fw_size[31:24];
            packet[26] = fw_size[23:16];
            packet[27] = fw_size[15:8];
            packet[28] = fw_size[7:0];
            calc_packet_crc(crc);
            packet[PACKET_LEN - 2] = crc[7:0];
            packet[PACKET_LEN - 1] = crc[15:8];
            $display("[IFE_TB] Send packet #0, file size = %0d", fw_size);
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
            $display("[IFE_TB] Send packet #%0d", packet_index + 1);
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
                $display("[IFE_TB] ERROR: UART receive timeout while waiting for %0s", ctx);
                $display("[IFE_TB] DEBUG: pc=0x%08x ctrl_state=0x%0x inst_ex=0x%08x x30=0x%08x x31=0x%08x succ=%b",
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.pc_pc_o,
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.ctrl_state_o,
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.ie_inst_o,
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.u_regs.regs[30],
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.u_regs.regs[31],
                         succ);
                $display("[IFE_TB] LAST_VALID: pc=0x%08x inst_ex=0x%08x ctrl_state=0x%0x",
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
                $display("[IFE_TB] ERROR: packet #%0d ACK failed, rx = 0x%02x", packet_no, ack_i);
                $finish;
            end
            $display("[IFE_TB] Packet #%0d ACK OK", packet_no);
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
                $display("[IFE_TB] ERROR: program did not reach success loop, x26=0x%08x x27=0x%08x pc=0x%08x",
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.u_regs.regs[26],
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.u_regs.regs[27],
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.pc_pc_o);
                $display("[IFE_TB] LAST_VALID: pc=0x%08x inst_ex=0x%08x ctrl_state=0x%0x",
                         last_valid_pc, last_valid_inst, last_valid_ctrl_state);
                dump_ram_contents;
                $finish;
            end
        end
    endtask

    task dump_ram_contents;
        integer ram_i;
        begin
            $display("[IFE_TB] RAM_DUMP_BEGIN");
            for (ram_i = 0; ram_i < `MemNum; ram_i = ram_i + 1) begin
                $display("[IFE_TB] RAM[%0d] = 0x%08x", ram_i, u_dut.u_bridge_slave_top.u_ram._ram[ram_i]);
            end
            $display("[IFE_TB] RAM_DUMP_END");
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
