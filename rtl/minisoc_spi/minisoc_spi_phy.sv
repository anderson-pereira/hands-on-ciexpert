//=============================================================================
// Project:     MiniSoC AES — RTL Design Track
// Module:      minisoc_spi_phy
// Description: SPI Mode 0 (CPOL=0, CPHA=0) Physical Layer for 40-bit fixed
//              frames (MSB-first, Out-of-Frame read response).
//              - Samples spi_mosi on posedge spi_sclk.
//              - Updates spi_miso on negedge spi_sclk.
//              - Shifts out 32-bit read data during bits [31:0] of the
//                return transaction (after the 8-bit header [39:32]).
//              - Wraps modulo-40 on bit_cnt, supporting both spi_cs_n toggled
//                frames and continuous multi-frame streaming with spi_cs_n=0.
//=============================================================================

module minisoc_spi_phy import minisoc_spi_pkg::*; (
    minisoc_spi_phy_if.peripheral phy_if,
    minisoc_spi_cdc_if.phy        cdc_if
);

    logic [5:0]  bit_cnt;   // Counts 0..39 rising edges (modulo-40 per frame)
    logic [38:0] rx_shift;  // Accumulates bits [39:1] prior to the 40th edge
    logic [31:0] tx_shift;  // Shifts out read response on negedge spi_sclk
    logic        miso_q;

    wire [39:0] assembled_frame = {rx_shift, phy_if.spi_mosi};

    // Assert completion pulse strictly on the 40th rising edge (bit_cnt == 39)
    assign cdc_if.rx_frame      = spi_frame_t'(assembled_frame);
    assign cdc_if.rx_frame_done = (!phy_if.spi_cs_n) && (bit_cnt == 6'd39);

    // Drive MISO low whenever deselected
    assign phy_if.spi_miso = (!phy_if.spi_cs_n) ? miso_q : 1'b0;

    //-------------------------------------------------------------------------
    // RX Deserializer & Modulo-40 Counter (posedge spi_sclk, async spi_cs_n=1)
    //-------------------------------------------------------------------------
    always_ff @(posedge phy_if.spi_sclk or posedge phy_if.spi_cs_n) begin
        if (phy_if.spi_cs_n) begin
            bit_cnt  <= 6'd0;
            rx_shift <= 39'd0;
        end else if (bit_cnt == 6'd39) begin
            bit_cnt  <= 6'd0;
            rx_shift <= 39'd0;
        end else begin
            bit_cnt  <= bit_cnt + 6'd1;
            rx_shift <= assembled_frame[38:0];
        end
    end

    //-------------------------------------------------------------------------
    // TX Serializer (negedge spi_sclk, cleared when spi_cs_n=1)
    // - On negedge 1 (bit_cnt == 1): captures stable tx_data_hold[31:0] while
    //   driving 0 during header bits [39:32].
    // - On negedge 8..39 (bit_cnt == 8..39): shifts out DATA[31:0] MSB-first
    //   so the controller samples DATA[31:0] on posedge 9..40.
    //-------------------------------------------------------------------------
    always_ff @(negedge phy_if.spi_sclk or posedge phy_if.spi_cs_n) begin
        if (phy_if.spi_cs_n) begin
            tx_shift <= 32'd0;
            miso_q   <= 1'b0;
        end else begin
            if (bit_cnt == 6'd1) begin
                tx_shift <= cdc_if.tx_data_hold;
                miso_q   <= 1'b0;
            end else if ((bit_cnt >= 6'd8) && (bit_cnt <= 6'd39)) begin
                miso_q   <= tx_shift[31];
                tx_shift <= {tx_shift[30:0], 1'b0};
            end else begin
                miso_q   <= 1'b0;
            end
        end
    end

endmodule : minisoc_spi_phy

