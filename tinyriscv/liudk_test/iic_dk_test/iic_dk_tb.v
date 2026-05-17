`timescale 1ns/1ps

module iic_dk_tb;

    localparam [31:0] ADDR_ADDR_REG = 32'h7001_0000;
    localparam [31:0] ADDR_DATA_IN  = 32'h7003_0000;

    localparam [1:0] IIC_WRITE = 2'b10;
    localparam [1:0] IIC_READ  = 2'b11;

    localparam [4:0] IDLE             = 5'd0;
    localparam [4:0] START            = 5'd1;
    localparam [4:0] ADDR_BYTE        = 5'd2;
    localparam [4:0] ADDR_BYTE_ACK    = 5'd3;
    localparam [4:0] POINTER_BYTE     = 5'd4;
    localparam [4:0] POINTER_BYTE_ACK = 5'd5;
    localparam [4:0] WE_HI_BYTE       = 5'd6;
    localparam [4:0] WE_HI_BYTE_ACK   = 5'd7;
    localparam [4:0] WE_LO_BYTE       = 5'd8;
    localparam [4:0] WE_LO_BYTE_ACK   = 5'd9;
    localparam [4:0] RD_HI_BYTE       = 5'd10;
    localparam [4:0] RD_HI_BYTE_ACK   = 5'd11;
    localparam [4:0] RD_LO_BYTE       = 5'd12;
    localparam [4:0] RD_LO_BYTE_ACK   = 5'd13;
    localparam [4:0] STOP             = 5'd14;

    localparam [15:0] SLAVE_READ_DATA = 16'h3c7e;

    reg clk;
    reg rst;
    reg [1:0] req_i;
    reg we_i;
    reg [31:0] addr_i;
    reg [31:0] data_i;

    wire [31:0] data_o;
    wire ack_o;
    wire scl;
    wire master_sda_o;
    wire master_sda_oe;
    tri1 sda;

    reg slave_sda_o;
    reg slave_sda_oe;

    reg [4:0] state_d;
    integer byte_bit_cnt;
    reg [7:0] sampled_byte;

    assign sda = master_sda_oe ? master_sda_o : 1'bz;
    assign sda = slave_sda_oe  ? slave_sda_o  : 1'bz;

    wire bus_conflict = master_sda_oe && slave_sda_oe && (master_sda_o != slave_sda_o);

    iic u_iic (
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

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

`ifdef FSDB
    initial begin
        $fsdbDumpfile("waves/iic_dk_tb.fsdb");
        $fsdbDumpvars(0, iic_dk_tb);
    end
`endif

    always @(*) begin
        slave_sda_o  = 1'b0;
        slave_sda_oe = 1'b0;

        case (u_iic.iic_cs)
            ADDR_BYTE_ACK,
            POINTER_BYTE_ACK,
            WE_HI_BYTE_ACK,
            WE_LO_BYTE_ACK: begin
                slave_sda_o  = 1'b0;
                slave_sda_oe = 1'b1;
            end

            RD_HI_BYTE: begin
                slave_sda_o  = SLAVE_READ_DATA[15 - u_iic.sda_counter[2:0]];
                slave_sda_oe = 1'b1;
            end

            RD_LO_BYTE: begin
                slave_sda_o  = SLAVE_READ_DATA[7 - u_iic.sda_counter[2:0]];
                slave_sda_oe = 1'b1;
            end

            default: begin
                slave_sda_o  = 1'b0;
                slave_sda_oe = 1'b0;
            end
        endcase
    end

    always @(posedge clk) begin
        if (bus_conflict) begin
            $display("[%0t] ERROR: SDA bus conflict. master=%0b slave=%0b state=%s",
                     $time, master_sda_o, slave_sda_o, state_name(u_iic.iic_cs));
            $fatal;
        end
    end

    always @(posedge clk) begin
        state_d <= u_iic.iic_cs;
        if (state_d !== u_iic.iic_cs) begin
            $display("[%0t] state=%s phase=%0d bit_cnt=%0d scl=%0b sda=%0b oe_m=%0b oe_s=%0b data_o=%08h",
                     $time, state_name(u_iic.iic_cs), u_iic.scl_phrase, u_iic.sda_counter,
                     scl, sda, master_sda_oe, slave_sda_oe, data_o);
        end
    end

    always @(posedge scl) begin
        if (master_sda_oe &&
            ((u_iic.iic_cs == ADDR_BYTE) || (u_iic.iic_cs == POINTER_BYTE) ||
             (u_iic.iic_cs == WE_HI_BYTE) || (u_iic.iic_cs == WE_LO_BYTE))) begin
            sampled_byte[7 - byte_bit_cnt[2:0]] <= sda;
            if (byte_bit_cnt == 7) begin
                $display("[%0t] master byte in %s = %02h",
                         $time, state_name(u_iic.iic_cs), {sampled_byte[7:1], sda});
                byte_bit_cnt <= 0;
            end else begin
                byte_bit_cnt <= byte_bit_cnt + 1;
            end
        end else begin
            byte_bit_cnt <= 0;
        end
    end

    initial begin
        $dumpfile("waves/iic_dk_tb.vcd");
        $dumpvars(0, iic_dk_tb);

        rst = 1'b0;
        req_i = 2'b00;
        we_i = 1'b0;
        addr_i = 32'h0;
        data_i = 32'h0;
        state_d = IDLE;
        byte_bit_cnt = 0;
        sampled_byte = 8'h00;

        repeat (20) @(posedge clk);
        rst = 1'b1;
        repeat (20) @(posedge clk);

        $display("---- WRITE transaction: addr=0x90 pointer=0 data=0xa55a ----");
        bus_write(ADDR_ADDR_REG, 32'h0000_0090);
        bus_write(ADDR_DATA_IN,  32'h0000_a55a);
        start_request(IIC_WRITE);
        wait_ack("write");

        repeat (200) @(posedge clk);

        $display("---- READ transaction: addr=0x91 slave returns 0x%04h ----", SLAVE_READ_DATA);
        bus_write(ADDR_ADDR_REG, 32'h0000_0091);
        start_request(IIC_READ);
        wait_ack("read");

        if (data_o[15:0] == SLAVE_READ_DATA) begin
            $display("PASS: read data_o[15:0] = 0x%04h", data_o[15:0]);
        end else begin
            $display("ERROR: read data_o[15:0] = 0x%04h, expected 0x%04h",
                     data_o[15:0], SLAVE_READ_DATA);
        end

        repeat (100) @(posedge clk);
        $display("Simulation done.");
        $finish;
    end

    task bus_write;
        input [31:0] addr;
        input [31:0] data;
        begin
            @(posedge clk);
            we_i <= 1'b1;
            addr_i <= addr;
            data_i <= data;
            @(posedge clk);
            we_i <= 1'b0;
            addr_i <= 32'h0;
            data_i <= 32'h0;
        end
    endtask

    task start_request;
        input [1:0] req;
        begin
            @(posedge clk);
            req_i <= req;
            @(posedge clk);
            req_i <= 2'b00;
        end
    endtask

    task wait_ack;
        input [8*16-1:0] name;
        integer timeout;
        begin
            timeout = 0;
            while ((ack_o !== 1'b1) && (timeout < 200000)) begin
                @(posedge clk);
                timeout = timeout + 1;
            end

            if (ack_o !== 1'b1) begin
                $display("ERROR: %0s transaction timeout", name);
                $fatal;
            end else begin
                $display("[%0t] %0s transaction ack, data_o=0x%08h", $time, name, data_o);
            end

            @(posedge clk);
        end
    endtask

    function [8*16-1:0] state_name;
        input [4:0] state;
        begin
            case (state)
                IDLE:             state_name = "IDLE";
                START:            state_name = "START";
                ADDR_BYTE:        state_name = "ADDR_BYTE";
                ADDR_BYTE_ACK:    state_name = "ADDR_BYTE_ACK";
                POINTER_BYTE:     state_name = "POINTER_BYTE";
                POINTER_BYTE_ACK: state_name = "POINTER_BYTE_ACK";
                WE_HI_BYTE:       state_name = "WE_HI_BYTE";
                WE_HI_BYTE_ACK:   state_name = "WE_HI_BYTE_ACK";
                WE_LO_BYTE:       state_name = "WE_LO_BYTE";
                WE_LO_BYTE_ACK:   state_name = "WE_LO_BYTE_ACK";
                RD_HI_BYTE:       state_name = "RD_HI_BYTE";
                RD_HI_BYTE_ACK:   state_name = "RD_HI_BYTE_ACK";
                RD_LO_BYTE:       state_name = "RD_LO_BYTE";
                RD_LO_BYTE_ACK:   state_name = "RD_LO_BYTE_ACK";
                STOP:             state_name = "STOP";
                default:          state_name = "UNKNOWN";
            endcase
        end
    endfunction

endmodule
