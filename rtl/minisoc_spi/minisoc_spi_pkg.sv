//=============================================================================
// Project:     MiniSoC AES — RTL Design Track
// Package:     minisoc_spi_pkg
// Description: Register map constants (6-bit), 40-bit SPI frame format,
//              AES mode encodings, and PLL divider encodings aligned with
//              DV_BlockGuide_MiniSoCAES_v1.0.0.
//=============================================================================

package minisoc_spi_pkg;

    //-------------------------------------------------------------------------
    // 1. Front-End Version Constant (Register 0x0D)
    //-------------------------------------------------------------------------
    localparam logic [31:0] SPI_FRONTEND_VERSION = 32'h0001_0000; // v1.0.0

    //-------------------------------------------------------------------------
    // 2. Register Map Constants (6-bit address: 0x00 to 0x3F)
    //-------------------------------------------------------------------------
    localparam logic [5:0] ADDR_KEY0           = 6'h00; // R/W: cfg_key[127:96]
    localparam logic [5:0] ADDR_KEY1           = 6'h01; // R/W: cfg_key[95:64]
    localparam logic [5:0] ADDR_KEY2           = 6'h02; // R/W: cfg_key[63:32]
    localparam logic [5:0] ADDR_KEY3           = 6'h03; // R/W: cfg_key[31:0]
    localparam logic [5:0] ADDR_IV0            = 6'h04; // R/W: cfg_iv[127:96]
    localparam logic [5:0] ADDR_IV1            = 6'h05; // R/W: cfg_iv[95:64]
    localparam logic [5:0] ADDR_IV2            = 6'h06; // R/W: cfg_iv[63:32]
    localparam logic [5:0] ADDR_IV3            = 6'h07; // R/W: cfg_iv[31:0]
    localparam logic [5:0] ADDR_COUNTER_HI     = 6'h08; // R/W: cfg_counter[63:32]
    localparam logic [5:0] ADDR_COUNTER_LO     = 6'h09; // R/W: cfg_counter[31:0]
    localparam logic [5:0] ADDR_NUM_BLOCKS     = 6'h0A; // R/W: 1..256 blocks
    localparam logic [5:0] ADDR_AES_CONTROL    = 6'h0B; // R/W: MODE[4:2], DECRYPT[1], START[0]
    localparam logic [5:0] ADDR_AES_STATUS     = 6'h0C; // R  : BLOCKS_DONE[11:3], ERROR[2], DONE[1], BUSY[0]
    localparam logic [5:0] ADDR_VERSION        = 6'h0D; // R  : Front-end version ID
    localparam logic [5:0] ADDR_SYSTEM_CONTROL = 6'h0E; // R/W: PLL_DIV_SEL[3:2], PLL_ENABLE[1], MEM_SEL_AES[0]
    localparam logic [5:0] ADDR_SYSTEM_STATUS  = 6'h0F; // R  : PLL_LOCKED[0]
    localparam logic [5:0] ADDR_NOP            = 6'h3F; // -  : Reserved for SPI read return transaction

    //-------------------------------------------------------------------------
    // 3. SPI 40-bit Frame Format (MSB-first, Section 5.2)
    //    [39]    RWb  : 0 = WRITE, 1 = READ request
    //    [38:33] ADDR : 6-bit CSR address
    //    [32]    RSV  : Reserved (sent as 0)
    //    [31:0]  DATA : 32-bit write payload (ignored on READ request)
    //-------------------------------------------------------------------------
    localparam int unsigned SPI_FRAME_BITS = 40;

    typedef struct packed {
        logic        rwb;
        logic [5:0]  addr;
        logic        rsv;
        logic [31:0] data;
    } spi_frame_t;

    //-------------------------------------------------------------------------
    // 4. AES Operation Modes (Section 8.2)
    //-------------------------------------------------------------------------
    typedef enum logic [2:0] {
        AES_MODE_ECB  = 3'b000,
        AES_MODE_CBC  = 3'b001,
        AES_MODE_PCBC = 3'b010,
        AES_MODE_CFB  = 3'b011,
        AES_MODE_OFB  = 3'b100,
        AES_MODE_CTR  = 3'b101
    } aes_mode_e;

    //-------------------------------------------------------------------------
    // 5. PLL Clock Divider Selections (Section 4.1)
    //-------------------------------------------------------------------------
    typedef enum logic [1:0] {
        PLL_DIV_1 = 2'b00, // 2.000 GHz
        PLL_DIV_2 = 2'b01, // 1.000 GHz
        PLL_DIV_4 = 2'b10, //   500 MHz
        PLL_DIV_8 = 2'b11  //   250 MHz
    } pll_div_sel_e;

endpackage : minisoc_spi_pkg

