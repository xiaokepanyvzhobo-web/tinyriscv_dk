`timescale 1ns/1ps

`include "defines.v"

module tinyriscv_soc_top_with_bridge_downloader_tb;

    localparam integer CLK_PERIOD_NS = 20;
`ifdef FAST_UART_SIM
    localparam integer UART_BIT_NS   = 180;
`elsif IVERILOG_FAST_SIM
    localparam integer UART_BIT_NS   = 180;
`else
    localparam integer UART_BIT_NS   = 8820;
`endif
    localparam integer PACKET_LEN    = 35;
    localparam integer PAYLOAD_LEN   = 32;
    localparam integer MAX_WORDS     = 4096;
    localparam integer MAX_BYTES     = MAX_WORDS * 4;

    reg clk;
    reg rst;
    reg uart_debug_pin;
    reg uart_rx_pin;
    reg jtag_TCK;
    reg jtag_TMS;
    reg jtag_TDI;
    reg spi_miso;

    wire over;
    wire succ;
    wire halted_ind;
    wire uart_tx_pin;
    wire jtag_TDO;
    wire spi_mosi;
    wire spi_ss;
    wire spi_clk;
    wire [1:0] gpio;

    reg [31:0] inst_words [0:MAX_WORDS - 1];
    reg [7:0]  fw_bytes   [0:MAX_BYTES - 1];
    reg [7:0]  packet     [0:PACKET_LEN - 1];

    integer fd;
    integer code;
    integer word_count;
    integer fw_size;
    integer total_packets;
    integer i;
    integer wait_cycles;
    reg [31:0] word_tmp;
    reg [15:0] crc;
    reg [7:0] ack;

    assign gpio = 2'bzz;

    always #(CLK_PERIOD_NS / 2) clk = ~clk;

    initial begin
        clk = 1'b0;
        rst = `RstEnable;
        uart_debug_pin = 1'b0;
        uart_rx_pin = 1'b1;
        jtag_TCK = 1'b1;
        jtag_TMS = 1'b1;
        jtag_TDI = 1'b1;
        spi_miso = 1'b0;

        load_inst_data;

        repeat (10) @(posedge clk);
        uart_debug_pin = 1'b1;
        rst = `RstDisable;

        repeat (200) @(posedge clk);
        send_first_packet;
        recv_uart_byte(ack);
        check_ack(ack, 0);

        for (i = 0; i < total_packets; i = i + 1) begin
            send_data_packet(i);
            recv_uart_byte(ack);
            check_ack(ack, i + 1);
        end

        $display("UART download finished: %0d bytes, %0d data packets", fw_size, total_packets);

        uart_debug_pin = 1'b0;
        repeat (20) @(posedge clk);

        rst = `RstEnable;
        repeat (10) @(posedge clk);
        rst = `RstDisable;

        wait_cycles = 0;
        while (((succ === 1'b1 ||  over === 1'b1) || (succ === 1'bx ||  over === 1'bx)) && wait_cycles < 1000000) begin
            wait_cycles = wait_cycles + 1;
            @(posedge clk);
        end

        $writememh("downloaded_rom_after_uart.hex",
                   u_dut.u_bridge_slave_top.u_rom._rom);
        $display("ROM image saved to downloaded_rom_after_uart.hex");

        if (succ === 1'b0) begin
            $display("FINAL PASS: succ=0, over=%b, wait_cycles=%0d", over, wait_cycles);
        end else begin
            $display("FINAL FAIL: succ=%b, over=%b, wait_cycles=%0d", succ, over, wait_cycles);
        end
        $finish;
    end

    initial begin
`ifdef FAST_UART_SIM
        #500000000;
`elsif IVERILOG_FAST_SIM
        #500000000;
`else
        #200000000;
`endif
        $display("Time Out.");
        $display("DEBUG: succ=%b over=%b uart_state=0x%04x remain=%0d rec_idx=%0d need=%0d wr_addr=0x%08x wr_idx0=%0d mem_ack=%b",
                 succ, over,
                 u_dut.u_tinyriscv_soc_top.u_uart_debug.state,
                 u_dut.u_tinyriscv_soc_top.u_uart_debug.remain_packet_count,
                 u_dut.u_tinyriscv_soc_top.u_uart_debug.rec_bytes_index,
                 u_dut.u_tinyriscv_soc_top.u_uart_debug.need_to_rec_bytes,
                 u_dut.u_tinyriscv_soc_top.u_uart_debug.write_mem_addr,
                 u_dut.u_tinyriscv_soc_top.u_uart_debug.write_mem_byte_index0,
                 u_dut.u_tinyriscv_soc_top.u_uart_debug.mem_write_ack_i);
        $display("DEBUG: bridge_master_cs=0x%02x bridge_slave_cs=0x%02x bmaster_TX=0x%02x bmaster_RX=0x%02x",
                 u_dut.u_tinyriscv_soc_top.u_bridge_master.cs,
                 u_dut.u_bridge_slave_top.u_bridge_slave.cs,
                 u_dut.bmaster_TX_data,
                 u_dut.bmaster_RX_data);
        $finish;
    end

    initial begin
`ifndef NO_DUMP
`ifdef FSDB
        $fsdbDumpfile("tinyriscv_soc_top_with_bridge_downloader_tb.fsdb");
        $fsdbDumpvars(0, tinyriscv_soc_top_with_bridge_downloader_tb);
        $fsdbDumpMDA(0, tinyriscv_soc_top_with_bridge_downloader_tb);
`else
        $dumpfile("tinyriscv_soc_top_with_bridge_downloader_tb.vcd");
        $dumpvars(0, tinyriscv_soc_top_with_bridge_downloader_tb);
`endif
`endif
    end

    task load_inst_data;
        begin
            word_count = 0;
            fd = $fopen("Baisc_Inst_Example/inst_andi.data", "r");
            if (fd == 0) begin
                $display("ERROR: cannot open Baisc_Inst_Example/inst_andi.data");
                $finish;
            end

            while (!$feof(fd)) begin
                code = $fscanf(fd, "%h\n", word_tmp);
                if (code == 1) begin
                    inst_words[word_count] = word_tmp;
                    fw_bytes[word_count * 4 + 0] = word_tmp[7:0];
                    fw_bytes[word_count * 4 + 1] = word_tmp[15:8];
                    fw_bytes[word_count * 4 + 2] = word_tmp[23:16];
                    fw_bytes[word_count * 4 + 3] = word_tmp[31:24];
                    word_count = word_count + 1;
                end
            end
            $fclose(fd);

            fw_size = word_count * 4;
            total_packets = (fw_size / PAYLOAD_LEN) + 1;
            $display("Loaded inst_andi.data: %0d words, %0d bytes, %0d packets",
                     word_count, fw_size, total_packets);
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

            packet[1]  = "i";
            packet[2]  = "n";
            packet[3]  = "s";
            packet[4]  = "t";
            packet[5]  = "_";
            packet[6]  = "a";
            packet[7]  = "d";
            packet[8]  = "d";
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

            $display("Send packet #0, file size = %0d", fw_size);
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

            $display("Send packet #%0d", packet_index + 1);
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
        integer bit_idx;
        begin
            wait (uart_tx_pin == 1'b0);
            #(UART_BIT_NS + (UART_BIT_NS / 2));
            for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                data[bit_idx] = uart_tx_pin;
                #(UART_BIT_NS);
            end
            #(UART_BIT_NS);
        end
    endtask

    task check_ack;
        input [7:0] ack_i;
        input integer packet_no;
        begin
            if (ack_i !== 8'h06) begin
                $display("ERROR: packet #%0d ACK failed, rx = 0x%02x", packet_no, ack_i);
                $finish;
            end
            $display("Packet #%0d ACK OK", packet_no);
        end
    endtask

    tinyriscv_soc_top_with_bridge u_dut(
        .clk(clk),
        .rst(rst),
        .over(over),
        .succ(succ),
        .halted_ind(halted_ind),
        .uart_debug_pin(uart_debug_pin),
        .uart_tx_pin(uart_tx_pin),
        .uart_rx_pin(uart_rx_pin),
        .gpio(gpio),
        .jtag_TCK(jtag_TCK),
        .jtag_TMS(jtag_TMS),
        .jtag_TDI(jtag_TDI),
        .jtag_TDO(jtag_TDO),
        .spi_miso(spi_miso),
        .spi_mosi(spi_mosi),
        .spi_ss(spi_ss),
        .spi_clk(spi_clk)
    );

endmodule
