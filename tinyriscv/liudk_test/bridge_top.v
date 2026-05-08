/*
 * bridge_top.v
 * Top-level wrapper that instantiates and connects:
 *   - bridge_master  (RIB -> 8-bit serial bridge)
 *   - bridge_slave   (8-bit serial bridge -> RAM/ROM access)
 *   - rom            (selected when addr[28] == 1'b0)
 *   - ram            (selected when addr[28] == 1'b1)
 *
 * Only the RIB-side signals are exposed at the top level.
 *
 * 注意：本文件假设的目录结构与其他源文件一致，即 defines.v 位于 ../core/ 下。
 * 如果你的目录结构不同，请同步修改下面的 `include 路径。
 */

`include "../rtl/core/defines.v"

module bridge_top (
    // 时钟和复位
    input  wire                  clk,
    input  wire                  rst,

    // RIB 接口（唯一对外暴露的总线）
    input  wire                  rib_req_i,    // 请求标志
    input  wire                  rib_we_i,     // 写使能
    input  wire [`MemAddrBus]    rib_addr_i,   // 访问地址
    input  wire [`MemBus]        rib_data_i,   // 写入数据
    output wire [`MemBus]        rib_data_o    // 读出数据
);

    //---------------------------------------------------------
    // 内部互连信号
    //---------------------------------------------------------

    // master <-> slave 8-bit 串行桥
    wire [`BridgeBus]   bmaster_TX_data;  // master -> slave
    wire [`BridgeBus]   bslave_TX_data;   // slave  -> master

    // master 输出的流水线 hold 标志（顶层未引出，悬空）
    wire                hold_flag;

    // slave <-> ram
    wire                ram_we;
    wire [`MemAddrBus]  ram_addr;
    wire [`MemBus]      ram_wdata;   // slave -> ram   (写数据)
    wire [`MemBus]      ram_rdata;   // ram   -> slave (读数据)

    // slave <-> rom
    wire                rom_we;
    wire [`MemAddrBus]  rom_addr;
    wire [`MemBus]      rom_wdata;   // slave -> rom
    wire [`MemBus]      rom_rdata;   // rom   -> slave

    //---------------------------------------------------------
    // bridge_master
    //---------------------------------------------------------
    bridge_master u_bridge_master (
        .clk             (clk            ),
        .rst             (rst            ),

        // RIB 输入接口
        .rib_req_i       (rib_req_i      ),
        .rib_we_i        (rib_we_i       ),
        .rib_addr_i      (rib_addr_i     ),
        .rib_data_i      (rib_data_i     ),
        .rib_data_o      (rib_data_o     ),

        // 与 slave 的串行接口
        .bmaster_RX_data (bslave_TX_data ),
        .bmaster_TX_data (bmaster_TX_data),

        // 流水线暂停标志（顶层未引出）
        .hold_flag_o     (hold_flag      )
    );

    //---------------------------------------------------------
    // bridge_slave
    //---------------------------------------------------------
    bridge_slave u_bridge_slave (
        .clk            (clk             ),
        .rst            (rst             ),

        // 与 master 的串行接口
        .bslave_RX_data (bmaster_TX_data ),
        .bslave_TX_data (bslave_TX_data  ),

        // 与 RAM 的接口
        .ram_we_o       (ram_we          ),
        .ram_addr_o     (ram_addr        ),
        .ram_data_o     (ram_wdata       ),
        .ram_data_i     (ram_rdata       ),

        // 与 ROM 的接口
        .rom_we_o       (rom_we          ),
        .rom_addr_o     (rom_addr        ),
        .rom_data_o     (rom_wdata       ),
        .rom_data_i     (rom_rdata       )
    );

    //---------------------------------------------------------
    // ROM (addr[28] == 1'b0 时被选中)
    //---------------------------------------------------------
    rom u_rom (
        .clk    (clk      ),
        .rst    (rst      ),
        .we_i   (rom_we   ),
        .addr_i (rom_addr ),
        .data_i (rom_wdata),
        .data_o (rom_rdata)
    );

    //---------------------------------------------------------
    // RAM (addr[28] == 1'b1 时被选中)
    //---------------------------------------------------------
    ram u_ram (
        .clk    (clk      ),
        .rst    (rst      ),
        .we_i   (ram_we   ),
        .addr_i (ram_addr ),
        .data_i (ram_wdata),
        .data_o (ram_rdata)
    );

endmodule