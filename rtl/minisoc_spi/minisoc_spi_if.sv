//=============================================================================
// Project:     MiniSoC AES — RTL Design Track
// Interfaces:  minisoc_spi_phy_if, minisoc_spi_cdc_if, minisoc_spi_csr_if
// Description: SystemVerilog interfaces and modports connecting the SPI PHY,
//              frame-level CDC bridge, and 32-bit CSR register bank.
//=============================================================================

//-----------------------------------------------------------------------------
// 1. External SPI Physical Bus Interface (Mode 0: CPOL=0, CPHA=0)
//-----------------------------------------------------------------------------
interface minisoc_spi_phy_if;
    logic spi_sclk;
    logic spi_cs_n;
    logic spi_mosi;
    logic spi_miso;

    modport peripheral (
        input  spi_sclk,
        input  spi_cs_n,
        input  spi_mosi,
        output spi_miso
    );

    modport controller (
        output spi_sclk,
        output spi_cs_n,
        output spi_mosi,
        input  spi_miso
    );
endinterface : minisoc_spi_phy_if


//-----------------------------------------------------------------------------
// 2. PHY <-> CDC Source-Side Interface (spi_sclk domain + static TX hold)
//-----------------------------------------------------------------------------
interface minisoc_spi_cdc_if;
    import minisoc_spi_pkg::*;

    logic        rx_frame_done; // 1-cycle pulse on 40th posedge spi_sclk
    spi_frame_t  rx_frame;      // Complete 40-bit received frame
    logic [31:0] tx_data_hold;  // Static 32-bit read response held in clk domain

    modport phy (
        output rx_frame_done,
        output rx_frame,
        input  tx_data_hold
    );

    modport cdc (
        input  rx_frame_done,
        input  rx_frame,
        output tx_data_hold
    );
endinterface : minisoc_spi_cdc_if


//-----------------------------------------------------------------------------
// 3. CDC <-> CSR Synchronous Bus Interface (always-on clk domain)
//-----------------------------------------------------------------------------
interface minisoc_spi_csr_if;
    import minisoc_spi_pkg::*;

    logic        frame_valid;  // 1-cycle pulse in clk domain when frame arrives
    spi_frame_t  frame;        // Synchronized 40-bit frame
    logic [31:0] rd_data_hold; // Latched 32-bit readback word for next SPI frame

    modport cdc (
        output frame_valid,
        output frame,
        input  rd_data_hold
    );

    modport csr (
        input  frame_valid,
        input  frame,
        output rd_data_hold
    );
endinterface : minisoc_spi_csr_if
