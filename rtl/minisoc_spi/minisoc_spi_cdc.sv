//=============================================================================
// Project:     MiniSoC AES — RTL Design Track
// Module:      minisoc_spi_cdc
// Description: Frame-level Clock Domain Crossing (CDC) bridge between
//              spi_sclk (up to 25 MHz) and always-on clk (2 GHz), implementing
//              Section 5.3 of DV_BlockGuide_MiniSoCAES_v1.0.0:
//              - Complete 40-bit frame held in rx_frame_hold (Data-Hold) and
//                signaled via toggle + 2-FF synchronizer into clk domain.
//              - Static 32-bit readback word held in rd_data_hold from clk
//                domain for Out-of-Frame MISO shift-out on next transaction.
//=============================================================================

module minisoc_spi_cdc import minisoc_spi_pkg::*; (
    input  logic                rst_n,
    input  logic                spi_sclk,
    input  logic                clk,
    minisoc_spi_cdc_if.cdc      cdc_if,
    minisoc_spi_csr_if.cdc      csr_if
);

    // Source domain (spi_sclk) registers — reset ONLY by global rst_n so that
    // deasserting spi_cs_n at the end of a frame never aborts an accepted toggle
    spi_frame_t rx_frame_hold;
    logic       req_toggle;

    // Destination domain (clk) 2-FF synchronizer + edge detector
    logic       req_meta;
    logic       req_sync;
    logic       req_seen;

    // Static read response held in clk domain for next SPI transaction
    assign cdc_if.tx_data_hold = csr_if.rd_data_hold;

    //-------------------------------------------------------------------------
    // Source Domain: Capture complete 40-bit frame on 40th posedge spi_sclk.
    // Note: Retains asynchronous rst_n because spi_sclk is idle (0) during
    // global reset; async clear prevents 'X' injection into the clk domain.
    //-------------------------------------------------------------------------
    always_ff @(posedge spi_sclk or negedge rst_n) begin
        if (!rst_n) begin
            rx_frame_hold <= '0;
            req_toggle    <= 1'b0;
        end else if (cdc_if.rx_frame_done) begin
            rx_frame_hold <= cdc_if.rx_frame;
            req_toggle    <= ~req_toggle;
        end
    end

    //-------------------------------------------------------------------------
    // Destination Domain: 2-FF toggle synchronizer into always-on clk
    // (Synchronous reset for optimal STA/QoR without recovery/removal arcs)
    //-------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            req_meta           <= 1'b0;
            req_sync           <= 1'b0;
            req_seen           <= 1'b0;
            csr_if.frame_valid <= 1'b0;
            csr_if.frame       <= '0;
        end else begin
            req_meta           <= req_toggle;
            req_sync           <= req_meta;
            csr_if.frame_valid <= 1'b0;

            if (req_sync != req_seen) begin
                req_seen           <= req_sync;
                csr_if.frame_valid <= 1'b1;
                csr_if.frame       <= rx_frame_hold;
            end
        end
    end

endmodule : minisoc_spi_cdc

