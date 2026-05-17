`timescale 1ns / 1ps

/*
 * Simple IIC master controller for LM75-like temperature sensors.
 *
 * Register map:
 *   0x7001_0000: slave address register
 *                [7:1] 7-bit slave address, [0] ignored by transfers
 *                [9:8] pointer register value
 *   0x7002_0000: IIC output data register, read result is stored here
 *   0x7003_0000: IIC input data register, low 16 bits are written to sensor
 *
 * SDA is open-drain style:
 *   SDA_oe_o = 1 drives SDA_o
 *   SDA_oe_o = 0 releases SDA line and external pull-up should make it high
 */

`include "defines.v"

module iic_controller #(
    parameter integer CLK_DIV = 250
)(
    input wire               clk,
    input wire               rst,

    // req_i[1] enable, req_i[0] direction: 0 = write, 1 = read.
    input wire [1:0]         req_i,
    input wire               we_i,
    input wire [`MemAddrBus] addr_i,
    input wire [`MemBus]     data_i,

    output reg [`MemBus]     data_o,
    output reg               ack_o,

    output wire              SCL_o,
    output reg               SDA_o,
    output reg               SDA_oe_o,
    input wire               SDA_i
);

    localparam [4:0] ST_IDLE        = 5'd0;
    localparam [4:0] ST_START_A     = 5'd1;
    localparam [4:0] ST_START_B     = 5'd2;
    localparam [4:0] ST_START_C     = 5'd3;
    localparam [4:0] ST_SEND_LOW    = 5'd4;
    localparam [4:0] ST_SEND_HIGH   = 5'd5;
    localparam [4:0] ST_SEND_FALL   = 5'd6;
    localparam [4:0] ST_ACK_LOW     = 5'd7;
    localparam [4:0] ST_ACK_HIGH    = 5'd8;
    localparam [4:0] ST_ACK_FALL    = 5'd9;
    localparam [4:0] ST_REP_A       = 5'd10;
    localparam [4:0] ST_REP_B       = 5'd11;
    localparam [4:0] ST_REP_C       = 5'd12;
    localparam [4:0] ST_REP_D       = 5'd13;
    localparam [4:0] ST_READ_LOW    = 5'd14;
    localparam [4:0] ST_READ_HIGH   = 5'd15;
    localparam [4:0] ST_READ_FALL   = 5'd16;
    localparam [4:0] ST_MACK_LOW    = 5'd17;
    localparam [4:0] ST_MACK_HIGH   = 5'd18;
    localparam [4:0] ST_MACK_FALL   = 5'd19;
    localparam [4:0] ST_STOP_A      = 5'd20;
    localparam [4:0] ST_STOP_B      = 5'd21;
    localparam [4:0] ST_STOP_C      = 5'd22;
    localparam [4:0] ST_DONE        = 5'd23;

    localparam [2:0] PH_WR_ADDR     = 3'd0;
    localparam [2:0] PH_WR_POINTER  = 3'd1;
    localparam [2:0] PH_WR_DATA_HI  = 3'd2;
    localparam [2:0] PH_WR_DATA_LO  = 3'd3;
    localparam [2:0] PH_RD_ADDR_W   = 3'd4;
    localparam [2:0] PH_RD_POINTER  = 3'd5;
    localparam [2:0] PH_RD_ADDR_R   = 3'd6;

    wire addr_slave_sel = (addr_i[23:16] == 8'h01);
    wire addr_out_sel   = (addr_i[23:16] == 8'h02);
    wire addr_in_sel    = (addr_i[23:16] == 8'h03);

    reg [`MemBus] slave_addr_reg;
    reg [`MemBus] output_data_reg;
    reg [`MemBus] input_data_reg;

    wire [`MemBus] slave_addr_new = (we_i == `WriteEnable && addr_slave_sel) ? data_i : slave_addr_reg;
    wire [`MemBus] input_data_new = (we_i == `WriteEnable && addr_in_sel)    ? data_i : input_data_reg;

    wire [7:0] slave_addr_wr_new = {slave_addr_new[7:1], 1'b0};
    wire [7:0] slave_addr_rd_new = {slave_addr_new[7:1], 1'b1};
    wire [7:0] pointer_new       = {6'h0, slave_addr_new[9:8]};
    wire [8:0] target_new        = {slave_addr_new[7:1], slave_addr_new[9:8]};
    wire [15:0] wr_data_new      = input_data_new[15:0];

    reg [4:0] state;
    reg [4:0] state_next;
    reg [2:0] phase;
    reg [2:0] bit_cnt;
    reg [15:0] clk_cnt;

    reg scl_reg;
    reg rw_latched;
    reg read_skip_pointer;
    reg master_nack;
    reg read_byte_index;
    reg nack_seen;

    reg cached_target_valid;
    reg [8:0] cached_target_reg;
    reg [8:0] target_latched;

    reg [7:0] slave_addr_wr;
    reg [7:0] slave_addr_rd;
    reg [7:0] pointer_byte;
    reg [7:0] tx_byte;
    reg [7:0] rx_shift;
    reg [15:0] write_data;
    reg [15:0] read_data_tmp;

    wire clk_tick = (clk_cnt == (CLK_DIV - 1));

    assign SCL_o = scl_reg;

    // Async register read. During completion ack, data_o holds the final result.
    always @ (*) begin
        if (ack_o == 1'b1) begin
            data_o = output_data_reg;
        end else begin
            case (1'b1)
                addr_slave_sel: data_o = slave_addr_reg;
                addr_out_sel:   data_o = output_data_reg;
                addr_in_sel:    data_o = input_data_reg;
                default:        data_o = `ZeroWord;
            endcase
        end
    end

    // 1) State register.
    always @ (posedge clk) begin
        if (rst == `RstEnable) begin
            state <= ST_IDLE;
        end else begin
            state <= state_next;
        end
    end

    // 2) Next-state logic.
    always @ (*) begin
        state_next = state;

        case (state)
            ST_IDLE: begin
                if (req_i[1] == 1'b1) begin
                    state_next = ST_START_A;
                end
            end

            ST_DONE: begin
                state_next = ST_IDLE;
            end

            default: begin
                if (clk_tick == 1'b1) begin
                    case (state)
                        ST_START_A:   state_next = ST_START_B;
                        ST_START_B:   state_next = ST_START_C;
                        ST_START_C:   state_next = ST_SEND_LOW;
                        ST_SEND_LOW:  state_next = ST_SEND_HIGH;
                        ST_SEND_HIGH: state_next = ST_SEND_FALL;
                        ST_SEND_FALL: state_next = (bit_cnt == 3'd0) ? ST_ACK_LOW : ST_SEND_LOW;
                        ST_ACK_LOW:   state_next = ST_ACK_HIGH;
                        ST_ACK_HIGH:  state_next = ST_ACK_FALL;

                        ST_ACK_FALL: begin
                            case (phase)
                                PH_WR_ADDR,
                                PH_WR_POINTER,
                                PH_WR_DATA_HI,
                                PH_RD_ADDR_W:  state_next = ST_SEND_LOW;
                                PH_WR_DATA_LO: state_next = ST_STOP_A;
                                PH_RD_POINTER: state_next = ST_REP_A;
                                PH_RD_ADDR_R:  state_next = ST_READ_LOW;
                                default:       state_next = ST_STOP_A;
                            endcase
                        end

                        ST_REP_A:     state_next = ST_REP_B;
                        ST_REP_B:     state_next = ST_REP_C;
                        ST_REP_C:     state_next = ST_REP_D;
                        ST_REP_D:     state_next = ST_SEND_LOW;
                        ST_READ_LOW:  state_next = ST_READ_HIGH;
                        ST_READ_HIGH: state_next = ST_READ_FALL;
                        ST_READ_FALL: state_next = (bit_cnt == 3'd0) ? ST_MACK_LOW : ST_READ_LOW;
                        ST_MACK_LOW:  state_next = ST_MACK_HIGH;
                        ST_MACK_HIGH: state_next = ST_MACK_FALL;
                        ST_MACK_FALL: state_next = (master_nack == 1'b1) ? ST_STOP_A : ST_READ_LOW;
                        ST_STOP_A:    state_next = ST_STOP_B;
                        ST_STOP_B:    state_next = ST_STOP_C;
                        ST_STOP_C:    state_next = ST_DONE;
                        default:      state_next = ST_IDLE;
                    endcase
                end
            end
        endcase
    end

    // 3) Datapath and registered outputs.
    always @ (posedge clk) begin
        if (rst == `RstEnable) begin
            slave_addr_reg      <= 32'h00000090;
            output_data_reg     <= `ZeroWord;
            input_data_reg      <= `ZeroWord;
            phase               <= PH_WR_ADDR;
            bit_cnt             <= 3'd7;
            clk_cnt             <= 16'h0;
            scl_reg             <= 1'b1;
            SDA_o               <= 1'b1;
            SDA_oe_o            <= 1'b0;
            ack_o               <= 1'b0;
            rw_latched          <= 1'b0;
            read_skip_pointer   <= 1'b0;
            master_nack         <= 1'b0;
            read_byte_index     <= 1'b0;
            nack_seen           <= 1'b0;
            cached_target_valid <= 1'b0;
            cached_target_reg   <= 9'h0;
            target_latched      <= 9'h0;
            slave_addr_wr       <= 8'h90;
            slave_addr_rd       <= 8'h91;
            pointer_byte        <= 8'h00;
            tx_byte             <= 8'h00;
            rx_shift            <= 8'h00;
            write_data          <= 16'h0000;
            read_data_tmp       <= 16'h0000;
        end else begin
            ack_o <= 1'b0;

            if (we_i == `WriteEnable) begin
                case (1'b1)
                    addr_slave_sel: slave_addr_reg  <= data_i;
                    addr_out_sel:   output_data_reg <= data_i;
                    addr_in_sel:    input_data_reg  <= data_i;
                    default: begin
                    end
                endcase
            end

            if (state == ST_IDLE || state == ST_DONE) begin
                clk_cnt <= 16'h0;
            end else if (clk_tick == 1'b1) begin
                clk_cnt <= 16'h0;
            end else begin
                clk_cnt <= clk_cnt + 1'b1;
            end

            if (state == ST_IDLE) begin
                scl_reg  <= 1'b1;
                SDA_o    <= 1'b1;
                SDA_oe_o <= 1'b0;

                if (req_i[1] == 1'b1) begin
                    rw_latched        <= req_i[0];
                    read_skip_pointer <= req_i[0] && cached_target_valid && (target_new == cached_target_reg);
                    slave_addr_wr     <= slave_addr_wr_new;
                    slave_addr_rd     <= slave_addr_rd_new;
                    pointer_byte      <= pointer_new;
                    target_latched    <= target_new;
                    write_data        <= wr_data_new;
                    read_data_tmp     <= 16'h0000;
                    rx_shift          <= 8'h00;
                    bit_cnt           <= 3'd7;
                    read_byte_index   <= 1'b0;
                    master_nack       <= 1'b0;
                    nack_seen         <= 1'b0;
                end
            end else if (state == ST_DONE) begin
                ack_o    <= 1'b1;
                scl_reg  <= 1'b1;
                SDA_o    <= 1'b1;
                SDA_oe_o <= 1'b0;
            end else if (clk_tick == 1'b1) begin
                case (state)
                    ST_START_A: begin
                        scl_reg  <= 1'b1;
                        SDA_o    <= 1'b1;
                        SDA_oe_o <= 1'b0;
                    end

                    ST_START_B: begin
                        scl_reg  <= 1'b1;
                        SDA_o    <= 1'b0;
                        SDA_oe_o <= 1'b1;
                    end

                    ST_START_C: begin
                        scl_reg  <= 1'b0;
                        SDA_o    <= 1'b0;
                        SDA_oe_o <= 1'b1;
                        bit_cnt  <= 3'd7;
                        tx_byte  <= (rw_latched && read_skip_pointer) ? slave_addr_rd : slave_addr_wr;
                        phase    <= (rw_latched == 1'b0) ? PH_WR_ADDR :
                                    (read_skip_pointer ? PH_RD_ADDR_R : PH_RD_ADDR_W);
                    end

                    ST_SEND_LOW: begin
                        scl_reg <= 1'b0;
                        if (tx_byte[bit_cnt] == 1'b0) begin
                            SDA_o    <= 1'b0;
                            SDA_oe_o <= 1'b1;
                        end else begin
                            SDA_o    <= 1'b1;
                            SDA_oe_o <= 1'b0;
                        end
                    end

                    ST_SEND_HIGH: begin
                        scl_reg <= 1'b1;
                    end

                    ST_SEND_FALL: begin
                        scl_reg <= 1'b0;
                        if (bit_cnt != 3'd0) begin
                            bit_cnt <= bit_cnt - 1'b1;
                        end
                    end

                    ST_ACK_LOW: begin
                        scl_reg  <= 1'b0;
                        SDA_o    <= 1'b1;
                        SDA_oe_o <= 1'b0;
                    end

                    ST_ACK_HIGH: begin
                        scl_reg <= 1'b1;
                        if (SDA_i == 1'b1) begin
                            nack_seen <= 1'b1;
                        end
                    end

                    ST_ACK_FALL: begin
                        scl_reg <= 1'b0;

                        case (phase)
                            PH_WR_ADDR: begin
                                tx_byte <= pointer_byte;
                                bit_cnt <= 3'd7;
                                phase   <= PH_WR_POINTER;
                            end

                            PH_WR_POINTER: begin
                                tx_byte <= write_data[15:8];
                                bit_cnt <= 3'd7;
                                phase   <= PH_WR_DATA_HI;
                                if (nack_seen == 1'b0) begin
                                    cached_target_valid <= 1'b1;
                                    cached_target_reg   <= target_latched;
                                end
                            end

                            PH_WR_DATA_HI: begin
                                tx_byte <= write_data[7:0];
                                bit_cnt <= 3'd7;
                                phase   <= PH_WR_DATA_LO;
                            end

                            PH_RD_ADDR_W: begin
                                tx_byte <= pointer_byte;
                                bit_cnt <= 3'd7;
                                phase   <= PH_RD_POINTER;
                            end

                            PH_RD_POINTER: begin
                                if (nack_seen == 1'b0) begin
                                    cached_target_valid <= 1'b1;
                                    cached_target_reg   <= target_latched;
                                end
                            end

                            PH_RD_ADDR_R: begin
                                bit_cnt         <= 3'd7;
                                read_byte_index <= 1'b0;
                                rx_shift        <= 8'h00;
                            end

                            default: begin
                            end
                        endcase
                    end

                    ST_REP_A: begin
                        scl_reg  <= 1'b0;
                        SDA_o    <= 1'b1;
                        SDA_oe_o <= 1'b0;
                    end

                    ST_REP_B: begin
                        scl_reg  <= 1'b1;
                        SDA_o    <= 1'b1;
                        SDA_oe_o <= 1'b0;
                    end

                    ST_REP_C: begin
                        scl_reg  <= 1'b1;
                        SDA_o    <= 1'b0;
                        SDA_oe_o <= 1'b1;
                    end

                    ST_REP_D: begin
                        scl_reg  <= 1'b0;
                        SDA_o    <= 1'b0;
                        SDA_oe_o <= 1'b1;
                        tx_byte  <= slave_addr_rd;
                        bit_cnt  <= 3'd7;
                        phase    <= PH_RD_ADDR_R;
                    end

                    ST_READ_LOW: begin
                        scl_reg  <= 1'b0;
                        SDA_o    <= 1'b1;
                        SDA_oe_o <= 1'b0;
                    end

                    ST_READ_HIGH: begin
                        scl_reg           <= 1'b1;
                        rx_shift[bit_cnt] <= SDA_i;
                    end

                    ST_READ_FALL: begin
                        scl_reg <= 1'b0;
                        if (bit_cnt == 3'd0) begin
                            if (read_byte_index == 1'b0) begin
                                read_data_tmp[15:8] <= rx_shift;
                                master_nack         <= 1'b0;
                            end else begin
                                read_data_tmp[7:0] <= rx_shift;
                                output_data_reg    <= {16'h0000, read_data_tmp[15:8], rx_shift};
                                master_nack        <= 1'b1;
                            end
                        end else begin
                            bit_cnt <= bit_cnt - 1'b1;
                        end
                    end

                    ST_MACK_LOW: begin
                        scl_reg <= 1'b0;
                        if (master_nack == 1'b1) begin
                            SDA_o    <= 1'b1;
                            SDA_oe_o <= 1'b0;
                        end else begin
                            SDA_o    <= 1'b0;
                            SDA_oe_o <= 1'b1;
                        end
                    end

                    ST_MACK_HIGH: begin
                        scl_reg <= 1'b1;
                    end

                    ST_MACK_FALL: begin
                        scl_reg  <= 1'b0;
                        SDA_o    <= 1'b1;
                        SDA_oe_o <= 1'b0;

                        if (master_nack == 1'b0) begin
                            read_byte_index <= 1'b1;
                            bit_cnt         <= 3'd7;
                            rx_shift        <= 8'h00;
                        end
                    end

                    ST_STOP_A: begin
                        scl_reg  <= 1'b0;
                        SDA_o    <= 1'b0;
                        SDA_oe_o <= 1'b1;
                    end

                    ST_STOP_B: begin
                        scl_reg  <= 1'b1;
                        SDA_o    <= 1'b0;
                        SDA_oe_o <= 1'b1;
                    end

                    ST_STOP_C: begin
                        scl_reg  <= 1'b1;
                        SDA_o    <= 1'b1;
                        SDA_oe_o <= 1'b0;
                    end

                    default: begin
                    end
                endcase
            end
        end
    end

endmodule
