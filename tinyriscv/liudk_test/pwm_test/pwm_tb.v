`timescale 1ns/1ps

`include "defines.v"

module pwm_tb;

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
    localparam integer EXPECTED_PWM_WRITES = 9;
    localparam integer UART_START_TIMEOUT_CYCLES = 200000;
    localparam integer PROGRAM_DONE_TIMEOUT_CYCLES = 1000000;

    reg clk;
    reg rst;
    reg uart_debug_pin;
    reg uart_rx_pin;

    wire succ;
    wire uart_tx_pin;
    tri1 io_sda;
    wire io_scl;
    wire [2:0] dut_pwm_o;

    reg [31:0] inst_words [0:MAX_WORDS - 1];
    reg [7:0] fw_bytes [0:MAX_BYTES - 1];
    reg [7:0] packet [0:PACKET_LEN - 1];
    reg [31:0] exp_addr [0:EXPECTED_PWM_WRITES - 1];
    reg [31:0] exp_data [0:EXPECTED_PWM_WRITES - 1];

    reg [8*256-1:0] inst_file;
    reg [8*256-1:0] rom_dump_file;

    integer fd;
    integer code;
    integer word_count;
    integer fw_size;
    integer total_packets;
    integer i;
    integer wait_cycles;
    integer pwm_pass;
    integer pwm_write_count;
    integer sample_idx;
    reg [31:0] word_tmp;
    reg [15:0] crc;
    reg [7:0] ack;
    reg [7:0] rx_byte;
    reg rx_ok;
    reg [31:0] last_valid_pc;
    reg [31:0] last_valid_inst;
    reg [3:0] last_valid_ctrl_state;

    wire cpu_pwm_write;
    wire [`MemAddrBus] cpu_pwm_addr;
    wire [`MemBus] cpu_pwm_data;
    wire [`MemBus] pwm_probe_data_o;
    wire [3:0] pwm_probe_o;

    always #(CLK_PERIOD_NS / 2) clk = ~clk;

    assign cpu_pwm_write =
        (rst == `RstDisable) &&
        (uart_debug_pin == 1'b0) &&
        (u_dut.u_tinyriscv_soc_top.u_tinyriscv.rib_ex_req_o == `RIB_REQ) &&
        (u_dut.u_tinyriscv_soc_top.u_tinyriscv.rib_ex_we_o == `WriteEnable) &&
        (u_dut.u_tinyriscv_soc_top.u_tinyriscv.rib_ex_addr_o[31:28] == 4'h6);

    assign cpu_pwm_addr = {4'h0, u_dut.u_tinyriscv_soc_top.u_tinyriscv.rib_ex_addr_o[27:0]};
    assign cpu_pwm_data = u_dut.u_tinyriscv_soc_top.u_tinyriscv.rib_ex_data_o;

    pwm u_pwm_probe (
        .clk    (clk),
        .rst    (rst),
        .we_i   (cpu_pwm_write),
        .addr_i (cpu_pwm_addr),
        .data_i (cpu_pwm_data),
        .data_o (pwm_probe_data_o),
        .PWM_o  (pwm_probe_o)
    );

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
            pwm_write_count <= 0;
        end else if (cpu_pwm_write) begin
            $display("[PWM_TB] PWM_STORE[%0d]: addr=0x%08x data=0x%08x pc=0x%08x",
                     pwm_write_count,
                     u_dut.u_tinyriscv_soc_top.u_tinyriscv.rib_ex_addr_o,
                     cpu_pwm_data,
                     u_dut.u_tinyriscv_soc_top.u_tinyriscv.pc_pc_o);

            if (pwm_write_count >= EXPECTED_PWM_WRITES) begin
                pwm_pass <= 0;
                $display("[PWM_TB] ERROR: unexpected extra PWM write addr=0x%08x data=0x%08x",
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.rib_ex_addr_o,
                         cpu_pwm_data);
            end else begin
                if (u_dut.u_tinyriscv_soc_top.u_tinyriscv.rib_ex_addr_o !== exp_addr[pwm_write_count]) begin
                    pwm_pass <= 0;
                    $display("[PWM_TB] ERROR: PWM write[%0d] address expected 0x%08x, got 0x%08x",
                             pwm_write_count,
                             exp_addr[pwm_write_count],
                             u_dut.u_tinyriscv_soc_top.u_tinyriscv.rib_ex_addr_o);
                end

                if (cpu_pwm_data !== exp_data[pwm_write_count]) begin
                    pwm_pass <= 0;
                    $display("[PWM_TB] ERROR: PWM write[%0d] data expected 0x%08x, got 0x%08x",
                             pwm_write_count,
                             exp_data[pwm_write_count],
                             cpu_pwm_data);
                end
            end

            pwm_write_count <= pwm_write_count + 1;
        end
    end

    initial begin
        inst_file = "liudk_test/pwm_test/PWM_inst.data";
        rom_dump_file = "liudk_test/pwm_test/build/downloaded_rom_after_uart.hex";
        if ($value$plusargs("INST_FILE=%s", inst_file)) begin end
        if ($value$plusargs("ROM_DUMP=%s", rom_dump_file)) begin end
    end

    initial begin
        exp_addr[0] = 32'h60000000; exp_data[0] = 32'h05f5e100;
        exp_addr[1] = 32'h60100000; exp_data[1] = 32'h02faf080;
        exp_addr[2] = 32'h60010000; exp_data[2] = 32'h02faf080;
        exp_addr[3] = 32'h60110000; exp_data[3] = 32'h017d7840;
        exp_addr[4] = 32'h60020000; exp_data[4] = 32'h003d0900;
        exp_addr[5] = 32'h60120000; exp_data[5] = 32'h001e8480;
        exp_addr[6] = 32'h60030000; exp_data[6] = 32'h007a1200;
        exp_addr[7] = 32'h60130000; exp_data[7] = 32'h003d0900;
        exp_addr[8] = 32'h60040000; exp_data[8] = 32'h0000000f;
    end

    initial begin
        clk = 1'b0;
        rst = `RstEnable;
        uart_debug_pin = 1'b0;
        uart_rx_pin = 1'b1;
        pwm_pass = 1;
        pwm_write_count = 0;

        print_expected_result;
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

        $display("[PWM_TB] UART_DEBUG download finished: %0d words, %0d bytes, %0d data packets",
                 word_count, fw_size, total_packets);
        $writememh(rom_dump_file, u_dut.u_bridge_slave_top.u_rom._rom);
        $display("[PWM_TB] ROM image saved to %0s", rom_dump_file);

        uart_debug_pin = 1'b0;
        uart_rx_pin = 1'b1;
        repeat (20) @(posedge clk);

        rst = `RstEnable;
        repeat (20) @(posedge clk);
        rst = `RstDisable;

        wait_uart_idle_high;
        $display("[PWM_TB] CPU released, waiting for PWM configuration writes...");

        wait_for_program_done;
        repeat (20) @(posedge clk);

        check_expected_write_count;
        check_pwm_registers;
        check_pwm_initial_output;
        sample_pwm_high_window;

        if (pwm_pass) begin
            $display("[PWM_TB] FINAL PASS: CPU wrote the expected PWM program sequence and real PWM output is valid.");
        end else begin
            $display("[PWM_TB] FINAL FAIL");
            $finish;
        end

        repeat (200) @(posedge clk);
        $finish;
    end

    initial begin
`ifndef NO_DUMP
`ifdef FSDB
        $fsdbDumpfile("liudk_test/pwm_test/build/pwm_tb.fsdb");
        $fsdbDumpvars(0, pwm_tb);
        $fsdbDumpMDA(0, pwm_tb);
`else
        $dumpfile("liudk_test/pwm_test/build/pwm_tb.vcd");
        $dumpvars(0, pwm_tb);
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
        $display("[PWM_TB] TIMEOUT: x26=0x%08x x27=0x%08x pc=0x%08x succ=%b pwm_writes=%0d",
                 u_dut.u_tinyriscv_soc_top.u_tinyriscv.u_regs.regs[26],
                 u_dut.u_tinyriscv_soc_top.u_tinyriscv.u_regs.regs[27],
                 u_dut.u_tinyriscv_soc_top.u_tinyriscv.pc_pc_o,
                 succ,
                 pwm_write_count);
        $display("[PWM_TB] LAST_VALID: pc=0x%08x inst_ex=0x%08x ctrl_state=0x%0x",
                 last_valid_pc, last_valid_inst, last_valid_ctrl_state);
        $finish;
    end

    task print_expected_result;
        begin
            $display("[PWM_TB] Expected program result:");
            $display("[PWM_TB]   ch0: A0=100000000, B0=50000000, duty=50%%");
            $display("[PWM_TB]   ch1: A1=50000000,  B1=25000000, duty=50%%");
            $display("[PWM_TB]   ch2: A2=4000000,   B2=2000000,  duty=50%%");
            $display("[PWM_TB]   ch3: A3=8000000,   B3=4000000,  duty=50%%");
            $display("[PWM_TB]   C[3:0]=4'b1111, all PWM outputs enabled.");
            $display("[PWM_TB] The TB checks CPU RIB writes, the real SoC PWM instance, and exported pwm_o[2:0].");
        end
    endtask

    task load_inst_data;
        begin
            word_count = 0;
            fd = $fopen(inst_file, "r");
            if (fd == 0) begin
                $display("[PWM_TB] ERROR: cannot open %0s", inst_file);
                $finish;
            end

            code = $fscanf(fd, "%h", word_tmp);
            while (code == 1) begin
                if (word_count >= MAX_WORDS) begin
                    $display("[PWM_TB] ERROR: firmware too large");
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
            $display("[PWM_TB] Loaded %0s: %0d words, %0d bytes, %0d data packets",
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
            packet[1]  = "P";
            packet[2]  = "W";
            packet[3]  = "M";
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
            $display("[PWM_TB] Send packet #0, file size = %0d", fw_size);
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
            $display("[PWM_TB] Send packet #%0d", packet_index + 1);
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
                $display("[PWM_TB] ERROR: UART receive timeout while waiting for %0s", ctx);
                $display("[PWM_TB] DEBUG: pc=0x%08x ctrl_state=0x%0x inst_ex=0x%08x x26=0x%08x x27=0x%08x succ=%b",
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.pc_pc_o,
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.ctrl_state_o,
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.ie_inst_o,
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.u_regs.regs[26],
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.u_regs.regs[27],
                         succ);
                $finish;
            end
        end
    endtask

    task check_ack;
        input [7:0] ack_i;
        input integer packet_no;
        begin
            if (ack_i !== 8'h06) begin
                $display("[PWM_TB] ERROR: packet #%0d ACK failed, rx = 0x%02x", packet_no, ack_i);
                $finish;
            end
            $display("[PWM_TB] Packet #%0d ACK OK", packet_no);
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
                   (wait_cycles < PROGRAM_DONE_TIMEOUT_CYCLES)) begin
                wait_cycles = wait_cycles + 1;
                @(posedge clk);
            end

            if (u_dut.u_tinyriscv_soc_top.u_tinyriscv.u_regs.regs[26] !== 32'h00000001) begin
                pwm_pass = 0;
                $display("[PWM_TB] ERROR: program did not reach success loop, x26=0x%08x x27=0x%08x pc=0x%08x",
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.u_regs.regs[26],
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.u_regs.regs[27],
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.pc_pc_o);
            end else begin
                $display("[PWM_TB] Program done: x26=0x%08x pc=0x%08x",
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.u_regs.regs[26],
                         u_dut.u_tinyriscv_soc_top.u_tinyriscv.pc_pc_o);
            end
        end
    endtask

    task check_expected_write_count;
        begin
            if (pwm_write_count !== EXPECTED_PWM_WRITES) begin
                pwm_pass = 0;
                $display("[PWM_TB] ERROR: expected %0d PWM writes, got %0d",
                         EXPECTED_PWM_WRITES, pwm_write_count);
            end else begin
                $display("[PWM_TB] PWM write count OK: %0d writes", pwm_write_count);
            end
        end
    endtask

    task check_pwm_registers;
        begin
            check_word("A0", u_dut.u_tinyriscv_soc_top.u_pwm.pwm_period0, 32'd100000000);
            check_word("B0", u_dut.u_tinyriscv_soc_top.u_pwm.pwm_high0,   32'd50000000);
            check_word("A1", u_dut.u_tinyriscv_soc_top.u_pwm.pwm_period1, 32'd50000000);
            check_word("B1", u_dut.u_tinyriscv_soc_top.u_pwm.pwm_high1,   32'd25000000);
            check_word("A2", u_dut.u_tinyriscv_soc_top.u_pwm.pwm_period2, 32'd4000000);
            check_word("B2", u_dut.u_tinyriscv_soc_top.u_pwm.pwm_high2,   32'd2000000);
            check_word("A3", u_dut.u_tinyriscv_soc_top.u_pwm.pwm_period3, 32'd8000000);
            check_word("B3", u_dut.u_tinyriscv_soc_top.u_pwm.pwm_high3,   32'd4000000);
            check_word("C",  u_dut.u_tinyriscv_soc_top.u_pwm.pwm_ctrl,    32'd15);
        end
    endtask

    task check_word;
        input [31:0] name;
        input [31:0] actual;
        input [31:0] expected;
        begin
            if (actual !== expected) begin
                pwm_pass = 0;
                $display("[PWM_TB] ERROR: %0s expected 0x%08x, got 0x%08x",
                         name, expected, actual);
            end else begin
                $display("[PWM_TB] %0s OK: 0x%08x", name, actual);
            end
        end
    endtask

    task check_pwm_initial_output;
        begin
            repeat (5) @(posedge clk);
            if (u_dut.u_tinyriscv_soc_top.pwm_out_tmp !== 4'b1111) begin
                pwm_pass = 0;
                $display("[PWM_TB] ERROR: internal PWM output expected 4'b1111 after enable, got 4'b%04b",
                         u_dut.u_tinyriscv_soc_top.pwm_out_tmp);
            end else begin
                $display("[PWM_TB] Internal PWM output after enable OK: 4'b%04b",
                         u_dut.u_tinyriscv_soc_top.pwm_out_tmp);
            end

            if (dut_pwm_o !== 3'b111) begin
                pwm_pass = 0;
                $display("[PWM_TB] ERROR: exported pwm_o expected 3'b111, got 3'b%03b", dut_pwm_o);
            end else begin
                $display("[PWM_TB] Exported pwm_o OK: 3'b%03b", dut_pwm_o);
            end
        end
    endtask

    task sample_pwm_high_window;
        begin
            for (sample_idx = 0; sample_idx < 128; sample_idx = sample_idx + 1) begin
                @(posedge clk);
                if (u_dut.u_tinyriscv_soc_top.pwm_out_tmp !== 4'b1111) begin
                    pwm_pass = 0;
                    $display("[PWM_TB] ERROR: real PWM output changed too early at sample %0d, got 4'b%04b",
                             sample_idx, u_dut.u_tinyriscv_soc_top.pwm_out_tmp);
                end
            end
            $display("[PWM_TB] PWM short high-window sample OK. Longer periods are checked by register values.");
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
        .io_scl(io_scl),
        .pwm_o(dut_pwm_o)
    );

endmodule
