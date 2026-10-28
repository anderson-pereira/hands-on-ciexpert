//=============================================================================
// Project:     MiniSoC AES — RTL Design Track
// Module:      minisoc_spi
// Description: SPI Front-End wrapper integrating the modular Physical Layer
//              (minisoc_spi_phy), Clock-Domain Crossing bridge
//              (minisoc_spi_cdc), and 32-bit CSR Bank (minisoc_spi_csr),
//              matching Section 5, Section 6, and Section 10 of
//              DV_BlockGuide_MiniSoCAES_v1.0.0.
//=============================================================================

module minisoc_spi import minisoc_spi_pkg::*; #(
    parameter logic [31:0] VERSION_ID = SPI_FRONTEND_VERSION
) (
    // Always-on Control Domain Clock & Global Reset
    input  logic         clk,
    input  logic         rst_n,

    // Top-Level SPI Serial Interface (Mode 0, up to 25 MHz)
    input  logic         spi_sclk,
    input  logic         spi_cs_n,
    input  logic         spi_mosi,
    output logic         spi_miso,

    // AES Configuration & Command Interface
    output logic [127:0] o_cfg_key,
    output logic [127:0] o_cfg_iv,
    output logic [63:0]  o_cfg_counter,
    output logic [31:0]  o_cfg_num_blocks,
    output logic [2:0]   o_cfg_mode,
    output logic         o_cfg_decrypt,
    output logic         o_aes_start,

    // AES Status Interface
    input  logic         i_aes_busy,
    input  logic         i_aes_done,
    input  logic         i_aes_error,
    input  logic [8:0]   i_aes_blocks_done,

    // System & PLL Control / Status Interface
    output logic         o_mem_sel_aes,
    output logic         o_pll_enable,
    output logic [1:0]   o_pll_div_sel,
    input  logic         i_pll_locked
);

    // Internal SystemVerilog Interfaces
    minisoc_spi_phy_if phy_if();
    minisoc_spi_cdc_if cdc_if();
    minisoc_spi_csr_if csr_if();

    assign phy_if.spi_sclk = spi_sclk;
    assign phy_if.spi_cs_n = spi_cs_n;
    assign phy_if.spi_mosi = spi_mosi;
    assign spi_miso        = phy_if.spi_miso;

    // 1. SPI Physical Layer (spi_sclk domain)
    minisoc_spi_phy u_phy (
        .phy_if (phy_if.peripheral),
        .cdc_if (cdc_if.phy)
    );

    // 2. Frame-Level Toggle CDC Bridge (spi_sclk <-> always-on clk)
    minisoc_spi_cdc u_cdc (
        .rst_n    (rst_n),
        .spi_sclk (spi_sclk),
        .clk      (clk),
        .cdc_if   (cdc_if.cdc),
        .csr_if   (csr_if.cdc)
    );

    // 3. 32-bit Control & Status Register Bank (always-on clk domain)
    minisoc_spi_csr #(
        .VERSION_ID (VERSION_ID)
    ) u_csr (
        .clk               (clk),
        .rst_n             (rst_n),
        .csr_if            (csr_if.csr),
        .o_cfg_key         (o_cfg_key),
        .o_cfg_iv          (o_cfg_iv),
        .o_cfg_counter     (o_cfg_counter),
        .o_cfg_num_blocks  (o_cfg_num_blocks),
        .o_cfg_mode        (o_cfg_mode),
        .o_cfg_decrypt     (o_cfg_decrypt),
        .o_aes_start       (o_aes_start),
        .i_aes_busy        (i_aes_busy),
        .i_aes_done        (i_aes_done),
        .i_aes_error       (i_aes_error),
        .i_aes_blocks_done (i_aes_blocks_done),
        .o_mem_sel_aes     (o_mem_sel_aes),
        .o_pll_enable      (o_pll_enable),
        .o_pll_div_sel     (o_pll_div_sel),
        .i_pll_locked      (i_pll_locked)
    );

endmodule : minisoc_spi

