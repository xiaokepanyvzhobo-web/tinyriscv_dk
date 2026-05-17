`timescale 1ns / 1ps

module lm75_slave_model (
    input  wire       sys_clk,
    input  wire       rst_n,
    input  wire [2:0] hw_addr,
    input  wire       scl_i,
    input  wire       sda_i,
    output reg        sda_o,
    output reg        sda_oe
);

    localparam [3:0] IDLE     = 4'd0;
    localparam [3:0] RX_ADDR  = 4'd1;
    localparam [3:0] ACK_ADDR = 4'd2;
    localparam [3:0] RX_PTR   = 4'd3;
    localparam [3:0] ACK_PTR  = 4'd4;
    localparam [3:0] TX_DATA  = 4'd5;
    localparam [3:0] WAIT_ACK = 4'd6;
    localparam [3:0] RX_DATA  = 4'd7;
    localparam [3:0] ACK_DATA = 4'd8;

    reg [2:0] scl_sr;
    reg [2:0] sda_sr;
    reg [3:0] state;
    reg [2:0] bit_cnt;
    reg [7:0] shift_reg;
    reg       rw_flag;
    reg       byte_idx;
    reg       bit_sampled;
    reg       master_ack;

    reg [7:0]  reg_conf;
    reg [15:0] reg_thyst;
    reg [15:0] reg_tos;
    reg [1:0]  ptr_reg;

    wire [15:0] reg_temp = 16'h1900;
    wire [6:0]  device_addr = {4'b1001, hw_addr};

    wire scl_sync = scl_sr[1];
    wire sda_sync = sda_sr[1];
    wire scl_rise = (scl_sr[2:1] == 2'b01);
    wire scl_fall = (scl_sr[2:1] == 2'b10);
    wire sda_rise = (sda_sr[2:1] == 2'b01);
    wire sda_fall = (sda_sr[2:1] == 2'b10);

    wire start_det = (scl_sync == 1'b1) && sda_fall;
    wire stop_det  = (scl_sync == 1'b1) && sda_rise;

    reg [7:0] current_tx_byte;

    always @ (*) begin
        case (ptr_reg)
            2'b00: current_tx_byte = (byte_idx == 1'b0) ? reg_temp[15:8]  : reg_temp[7:0];
            2'b01: current_tx_byte = reg_conf;
            2'b10: current_tx_byte = (byte_idx == 1'b0) ? reg_thyst[15:8] : reg_thyst[7:0];
            2'b11: current_tx_byte = (byte_idx == 1'b0) ? reg_tos[15:8]   : reg_tos[7:0];
            default: current_tx_byte = 8'hff;
        endcase
    end

    always @ (posedge sys_clk or negedge rst_n) begin
        if (!rst_n) begin
            scl_sr <= 3'b111;
            sda_sr <= 3'b111;
        end else begin
            scl_sr <= {scl_sr[1:0], scl_i};
            sda_sr <= {sda_sr[1:0], sda_i};
        end
    end

    task drive_sda_bit;
        input bit_value;
        begin
            if (bit_value == 1'b0) begin
                sda_o  <= 1'b0;
                sda_oe <= 1'b1;
            end else begin
                sda_o  <= 1'b1;
                sda_oe <= 1'b0;
            end
        end
    endtask

    always @ (posedge sys_clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= IDLE;
            bit_cnt     <= 3'd7;
            shift_reg   <= 8'h00;
            rw_flag     <= 1'b0;
            byte_idx    <= 1'b0;
            bit_sampled <= 1'b0;
            master_ack  <= 1'b0;
            ptr_reg     <= 2'b00;
            reg_conf    <= 8'h00;
            reg_thyst   <= 16'h4b00;
            reg_tos     <= 16'h5000;
            sda_o       <= 1'b1;
            sda_oe      <= 1'b0;
        end else begin
            if (start_det) begin
                state       <= RX_ADDR;
                bit_cnt     <= 3'd7;
                shift_reg   <= 8'h00;
                byte_idx    <= 1'b0;
                bit_sampled <= 1'b0;
                master_ack  <= 1'b0;
                sda_o       <= 1'b1;
                sda_oe      <= 1'b0;
            end else if (stop_det) begin
                state       <= IDLE;
                bit_sampled <= 1'b0;
                master_ack  <= 1'b0;
                sda_o       <= 1'b1;
                sda_oe      <= 1'b0;
            end else if (scl_rise) begin
                case (state)
                    RX_ADDR,
                    RX_PTR,
                    RX_DATA: begin
                        shift_reg[bit_cnt] <= sda_sync;
                        bit_sampled        <= 1'b1;
                    end

                    WAIT_ACK: begin
                        master_ack <= (sda_sync == 1'b0);
                    end

                    default: begin
                    end
                endcase
            end else if (scl_fall) begin
                case (state)
                    RX_ADDR: begin
                        if (bit_sampled) begin
                            bit_sampled <= 1'b0;
                            if (bit_cnt == 3'd0) begin
                                if (shift_reg[7:1] == device_addr) begin
                                    state   <= ACK_ADDR;
                                    rw_flag <= shift_reg[0];
                                    sda_o   <= 1'b0;
                                    sda_oe  <= 1'b1;
                                end else begin
                                    state  <= IDLE;
                                    sda_o  <= 1'b1;
                                    sda_oe <= 1'b0;
                                end
                            end else begin
                                bit_cnt <= bit_cnt - 1'b1;
                            end
                        end
                    end

                    ACK_ADDR: begin
                        if (rw_flag) begin
                            state    <= TX_DATA;
                            bit_cnt  <= 3'd7;
                            byte_idx <= 1'b0;
                            drive_sda_bit(current_tx_byte[7]);
                        end else begin
                            state       <= RX_PTR;
                            bit_cnt     <= 3'd7;
                            shift_reg   <= 8'h00;
                            bit_sampled <= 1'b0;
                            sda_o       <= 1'b1;
                            sda_oe      <= 1'b0;
                        end
                    end

                    RX_PTR: begin
                        if (bit_sampled) begin
                            bit_sampled <= 1'b0;
                            if (bit_cnt == 3'd0) begin
                                state   <= ACK_PTR;
                                ptr_reg <= shift_reg[1:0];
                                sda_o   <= 1'b0;
                                sda_oe  <= 1'b1;
                            end else begin
                                bit_cnt <= bit_cnt - 1'b1;
                            end
                        end
                    end

                    ACK_PTR: begin
                        state       <= RX_DATA;
                        bit_cnt     <= 3'd7;
                        byte_idx    <= 1'b0;
                        shift_reg   <= 8'h00;
                        bit_sampled <= 1'b0;
                        sda_o       <= 1'b1;
                        sda_oe      <= 1'b0;
                    end

                    TX_DATA: begin
                        if (bit_cnt == 3'd0) begin
                            state      <= WAIT_ACK;
                            master_ack <= 1'b0;
                            sda_o      <= 1'b1;
                            sda_oe     <= 1'b0;
                        end else begin
                            bit_cnt <= bit_cnt - 1'b1;
                            drive_sda_bit(current_tx_byte[bit_cnt - 1'b1]);
                        end
                    end

                    WAIT_ACK: begin
                        if ((master_ack == 1'b0) || (ptr_reg == 2'b01) || (byte_idx == 1'b1)) begin
                            state  <= IDLE;
                            sda_o  <= 1'b1;
                            sda_oe <= 1'b0;
                        end else begin
                            state    <= TX_DATA;
                            bit_cnt  <= 3'd7;
                            byte_idx <= 1'b1;
                            drive_sda_bit(current_tx_byte[7]);
                        end
                    end

                    RX_DATA: begin
                        if (bit_sampled) begin
                            bit_sampled <= 1'b0;
                            if (bit_cnt == 3'd0) begin
                                state  <= ACK_DATA;
                                sda_o  <= 1'b0;
                                sda_oe <= 1'b1;
                                case (ptr_reg)
                                    2'b01: reg_conf <= shift_reg;
                                    2'b10: begin
                                        if (byte_idx == 1'b0) begin
                                            reg_thyst[15:8] <= shift_reg;
                                        end else begin
                                            reg_thyst[7:0] <= shift_reg;
                                        end
                                    end
                                    2'b11: begin
                                        if (byte_idx == 1'b0) begin
                                            reg_tos[15:8] <= shift_reg;
                                        end else begin
                                            reg_tos[7:0] <= shift_reg;
                                        end
                                    end
                                    default: begin
                                    end
                                endcase
                            end else begin
                                bit_cnt <= bit_cnt - 1'b1;
                            end
                        end
                    end

                    ACK_DATA: begin
                        if ((ptr_reg == 2'b01) || (byte_idx == 1'b1)) begin
                            state  <= IDLE;
                            sda_o  <= 1'b1;
                            sda_oe <= 1'b0;
                        end else begin
                            state       <= RX_DATA;
                            bit_cnt     <= 3'd7;
                            byte_idx    <= 1'b1;
                            shift_reg   <= 8'h00;
                            bit_sampled <= 1'b0;
                            sda_o       <= 1'b1;
                            sda_oe      <= 1'b0;
                        end
                    end

                    default: begin
                    end
                endcase
            end
        end
    end

endmodule
