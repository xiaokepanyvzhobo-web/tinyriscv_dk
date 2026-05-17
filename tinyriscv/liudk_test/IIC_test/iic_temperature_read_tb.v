`timescale 1ns / 1ps

`include "defines.v"

module iic_temperature_read_tb;

    localparam integer CLK_PERIOD_NS = 20;
    localparam [31:0]  REG_SLAVE_ADDR = 32'h7001_0000;
    localparam [31:0]  REG_OUTPUT     = 32'h7002_0000;
    localparam [15:0]  TRUE_TEMP_DATA = 16'h1900;
    localparam [31:0]  LM75_ADDR_TEMP = 32'h0000_0090; // {7'h48, write_bit=0}, pointer=2'b00

    reg clk;
    reg rst;
    reg [1:0] req_i;
    reg we_i;
    reg [`MemAddrBus] addr_i;
    reg [`MemBus] data_i;

    wire [`MemBus] data_o;
    wire ack_o;
    wire scl;
    wire sda;
    wire master_sda_o;
    wire master_sda_oe;
    wire slave_sda_o;
    wire slave_sda_oe;

    integer timeout_count;

`ifdef DEBUG_IIC_TB
    reg [4:0] dbg_master_state_d;
    reg [3:0] dbg_slave_state_d;
`endif

    assign sda = master_sda_oe ? master_sda_o : 1'bz;
    assign sda = slave_sda_oe  ? slave_sda_o  : 1'bz;
    pullup(sda);

    iic_controller #(
        .CLK_DIV(16)
    ) u_iic_controller (
        .clk      (clk),
        .rst      (rst),
        .req_i    (req_i),
        .we_i     (we_i),
        .addr_i   (addr_i),
        .data_i   (data_i),
        .data_o   (data_o),
        .ack_o    (ack_o),
        .SCL_o    (scl),
        .SDA_o    (master_sda_o),
        .SDA_oe_o (master_sda_oe),
        .SDA_i    (sda)
    );

    lm75_slave_model u_lm75_slave (
        .sys_clk (clk),
        .rst_n   (rst),
        .hw_addr (3'b000),
        .scl_i   (scl),
        .sda_i   (sda),
        .sda_o   (slave_sda_o),
        .sda_oe  (slave_sda_oe)
    );

`ifdef DEBUG_IIC_TB
    always @ (posedge clk) begin
        dbg_master_state_d <= u_iic_controller.state;
        dbg_slave_state_d  <= u_lm75_slave.state;

        if (u_iic_controller.state != dbg_master_state_d) begin
            $display("DBG %0t master_state=%0d phase=%0d bit=%0d skip=%0b sda=%b scl=%b",
                     $time, u_iic_controller.state, u_iic_controller.phase,
                     u_iic_controller.bit_cnt, u_iic_controller.read_skip_pointer,
                     sda, scl);
        end

        if (u_lm75_slave.state != dbg_slave_state_d) begin
            $display("DBG %0t slave_state=%0d bit=%0d rw=%0b ptr=%0d byte=%0b shift=0x%02h sda_oe=%0b",
                     $time, u_lm75_slave.state, u_lm75_slave.bit_cnt,
                     u_lm75_slave.rw_flag, u_lm75_slave.ptr_reg,
                     u_lm75_slave.byte_idx, u_lm75_slave.shift_reg,
                     u_lm75_slave.sda_oe);
        end
    end
`endif

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD_NS / 2) clk = ~clk;
    end

    initial begin
        $dumpfile("waves/iic_temperature_read_tb.vcd");
        repeat (2) @(posedge clk);
        $dumpvars(0, iic_temperature_read_tb);
    end

    task bus_write;
        input [31:0] wr_addr;
        input [31:0] wr_data;
        begin
            @(posedge clk);
            addr_i <= wr_addr;
            data_i <= wr_data;
            we_i   <= 1'b1;
            @(posedge clk);
            we_i   <= 1'b0;
            addr_i <= 32'h0;
            data_i <= 32'h0;
        end
    endtask

    task issue_read_req;
        begin
            @(posedge clk);
            req_i <= 2'b11;
            @(posedge clk);
            req_i <= 2'b00;
        end
    endtask

    task wait_and_check_temperature;
        input [8*32-1:0] case_name;
        input            expect_skip_pointer;
        begin
            timeout_count = 0;
            while (ack_o !== 1'b1 && timeout_count < 20000) begin
                timeout_count = timeout_count + 1;
                @(posedge clk);
            end

            if (ack_o !== 1'b1) begin
                $display("TEST FAIL: %0s timeout waiting for ack_o", case_name);
                $finish;
            end

            if (u_iic_controller.read_skip_pointer !== expect_skip_pointer) begin
                $display("TEST FAIL: %0s read_skip_pointer=%0b expected=%0b",
                         case_name, u_iic_controller.read_skip_pointer, expect_skip_pointer);
                $finish;
            end

            if (data_o[15:0] !== TRUE_TEMP_DATA) begin
                $display("TEST FAIL: %0s ack_o=1 data_o=0x%08h expected_temp=0x%04h",
                         case_name, data_o, TRUE_TEMP_DATA);
                $finish;
            end

            $display("TEST PASS: %0s ack_o=1 data_o=0x%08h temp=0x%04h skip_pointer=%0b",
                     case_name, data_o, data_o[15:0], u_iic_controller.read_skip_pointer);
            @(posedge clk);
        end
    endtask

    initial begin
        rst    = `RstEnable;
        req_i  = 2'b00;
        we_i   = 1'b0;
        addr_i = 32'h0;
        data_i = 32'h0;

        repeat (10) @(posedge clk);
        rst = `RstDisable;
        repeat (10) @(posedge clk);

        bus_write(REG_SLAVE_ADDR, LM75_ADDR_TEMP);

        issue_read_req();
        wait_and_check_temperature("full pointer temperature read", 1'b0);

        issue_read_req();
        wait_and_check_temperature("cached pointer temperature read", 1'b1);

        $display("FINAL PASS: LM75 temperature read matched true data 0x%04h", TRUE_TEMP_DATA);
        repeat (20) @(posedge clk);
        $finish;
    end

    initial begin
        #5000000;
        $display("TEST FAIL: global timeout");
        $finish;
    end

endmodule
