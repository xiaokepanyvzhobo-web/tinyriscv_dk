library verilog;
use verilog.vl_types.all;
entity iic is
    generic(
        IDLE            : vl_logic_vector(0 to 4) := (Hi0, Hi0, Hi0, Hi0, Hi0);
        START           : vl_logic_vector(0 to 4) := (Hi0, Hi0, Hi0, Hi0, Hi1);
        ADDR_BYTE       : vl_logic_vector(0 to 4) := (Hi0, Hi0, Hi0, Hi1, Hi0);
        ADDR_BYTE_ACK   : vl_logic_vector(0 to 4) := (Hi0, Hi0, Hi0, Hi1, Hi1);
        POINTER_BYTE    : vl_logic_vector(0 to 4) := (Hi0, Hi0, Hi1, Hi0, Hi0);
        POINTER_BYTE_ACK: vl_logic_vector(0 to 4) := (Hi0, Hi0, Hi1, Hi0, Hi1);
        WE_HI_BYTE      : vl_logic_vector(0 to 4) := (Hi0, Hi0, Hi1, Hi1, Hi0);
        WE_HI_BYTE_ACK  : vl_logic_vector(0 to 4) := (Hi0, Hi0, Hi1, Hi1, Hi1);
        WE_LO_BYTE      : vl_logic_vector(0 to 4) := (Hi0, Hi1, Hi0, Hi0, Hi0);
        WE_LO_BYTE_ACK  : vl_logic_vector(0 to 4) := (Hi0, Hi1, Hi0, Hi0, Hi1);
        RD_HI_BYTE      : vl_logic_vector(0 to 4) := (Hi0, Hi1, Hi0, Hi1, Hi0);
        RD_HI_BYTE_ACK  : vl_logic_vector(0 to 4) := (Hi0, Hi1, Hi0, Hi1, Hi1);
        RD_LO_BYTE      : vl_logic_vector(0 to 4) := (Hi0, Hi1, Hi1, Hi0, Hi0);
        RD_LO_BYTE_ACK  : vl_logic_vector(0 to 4) := (Hi0, Hi1, Hi1, Hi0, Hi1);
        STOP            : vl_logic_vector(0 to 4) := (Hi0, Hi1, Hi1, Hi1, Hi0)
    );
    port(
        clk             : in     vl_logic;
        rst             : in     vl_logic;
        req_i           : in     vl_logic_vector(1 downto 0);
        we_i            : in     vl_logic;
        addr_i          : in     vl_logic_vector(31 downto 0);
        data_i          : in     vl_logic_vector(31 downto 0);
        data_o          : out    vl_logic_vector(31 downto 0);
        ack_o           : out    vl_logic;
        SCL_o           : out    vl_logic;
        SDA_o           : out    vl_logic;
        SDA_oe_o        : out    vl_logic;
        SDA_i           : in     vl_logic
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of IDLE : constant is 1;
    attribute mti_svvh_generic_type of START : constant is 1;
    attribute mti_svvh_generic_type of ADDR_BYTE : constant is 1;
    attribute mti_svvh_generic_type of ADDR_BYTE_ACK : constant is 1;
    attribute mti_svvh_generic_type of POINTER_BYTE : constant is 1;
    attribute mti_svvh_generic_type of POINTER_BYTE_ACK : constant is 1;
    attribute mti_svvh_generic_type of WE_HI_BYTE : constant is 1;
    attribute mti_svvh_generic_type of WE_HI_BYTE_ACK : constant is 1;
    attribute mti_svvh_generic_type of WE_LO_BYTE : constant is 1;
    attribute mti_svvh_generic_type of WE_LO_BYTE_ACK : constant is 1;
    attribute mti_svvh_generic_type of RD_HI_BYTE : constant is 1;
    attribute mti_svvh_generic_type of RD_HI_BYTE_ACK : constant is 1;
    attribute mti_svvh_generic_type of RD_LO_BYTE : constant is 1;
    attribute mti_svvh_generic_type of RD_LO_BYTE_ACK : constant is 1;
    attribute mti_svvh_generic_type of STOP : constant is 1;
end iic;
