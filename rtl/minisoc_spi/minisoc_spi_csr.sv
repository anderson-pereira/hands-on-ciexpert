//=============================================================================
// Project:     MiniSoC AES — RTL Design Track
// Module:      minisoc_spi_csr
// Description: 32-bit Control and Status Register (CSR) bank operating in the
//              always-on reference clock domain (clk) to support PLL bootstrap
//              (Sections 2.2 and 6 of DV_BlockGuide_MiniSoCAES_v1.0.0).
//=============================================================================

module minisoc_spi_csr import minisoc_spi_pkg::*; #(
    parameter logic [31:0] VERSION_ID = SPI_FRONTEND_VERSION
) (
    input  logic                  clk,
    input  logic                  rst_n,

    // Synchronized Frame Interface (clk domain)
    minisoc_spi_csr_if.csr        csr_if,

    // AES Configuration & Command Outputs
    output logic [127:0]          o_cfg_key,
    output logic [127:0]          o_cfg_iv,
    output logic [63:0]           o_cfg_counter,
    output logic [31:0]           o_cfg_num_blocks,
    output logic [2:0]            o_cfg_mode,
    output logic                  o_cfg_decrypt,
    output logic                  o_aes_start,

    // AES Status Inputs
    input  logic                  i_aes_busy,
    input  logic                  i_aes_done,
    input  logic                  i_aes_error,
    input  logic [8:0]            i_aes_blocks_done,

    // System & PLL Control / Status
    output logic                  o_mem_sel_aes,
    output logic                  o_pll_enable,
    output logic [1:0]            o_pll_div_sel,
    input  logic                  i_pll_locked
);

    //-------------------------------------------------------------------------
    // Internal 32-bit CSR Storage
    //-------------------------------------------------------------------------
    logic [31:0] key_reg [0:3];
    logic [31:0] iv_reg  [0:3];
    logic [31:0] counter_hi_reg;
    logic [31:0] counter_lo_reg;
    logic [31:0] num_blocks_reg;
    logic [2:0]  aes_mode_reg;
    logic        aes_decrypt_reg;
    logic        mem_sel_aes_reg;
    logic        pll_enable_reg;
    logic [1:0]  pll_div_sel_reg;
    logic [31:0] rd_mux_data;

    // Continuous Configuration Assignments
    assign o_cfg_key        = {key_reg[0], key_reg[1], key_reg[2], key_reg[3]};
    assign o_cfg_iv         = {iv_reg[0],  iv_reg[1],  iv_reg[2],  iv_reg[3]};
    assign o_cfg_counter    = {counter_hi_reg, counter_lo_reg};
    assign o_cfg_num_blocks = num_blocks_reg;
    assign o_cfg_mode       = aes_mode_reg;
    assign o_cfg_decrypt    = aes_decrypt_reg;
    assign o_mem_sel_aes    = mem_sel_aes_reg;
    assign o_pll_enable     = pll_enable_reg;
    assign o_pll_div_sel    = pll_div_sel_reg;

    //-------------------------------------------------------------------------
    // Combinational Read Multiplexer (Address Decode 0x00..0x0F)
    //-------------------------------------------------------------------------
    always_comb begin
        rd_mux_data = 32'h0000_0000;
        case (csr_if.frame.addr)
            ADDR_KEY0:           rd_mux_data = key_reg[0];
            ADDR_KEY1:           rd_mux_data = key_reg[1];
            ADDR_KEY2:           rd_mux_data = key_reg[2];
            ADDR_KEY3:           rd_mux_data = key_reg[3];
            ADDR_IV0:            rd_mux_data = iv_reg[0];
            ADDR_IV1:            rd_mux_data = iv_reg[1];
            ADDR_IV2:            rd_mux_data = iv_reg[2];
            ADDR_IV3:            rd_mux_data = iv_reg[3];
            ADDR_COUNTER_HI:     rd_mux_data = counter_hi_reg;
            ADDR_COUNTER_LO:     rd_mux_data = counter_lo_reg;
            ADDR_NUM_BLOCKS:     rd_mux_data = num_blocks_reg;
            ADDR_AES_CONTROL:    rd_mux_data = {27'd0, aes_mode_reg, aes_decrypt_reg, 1'b0};
            ADDR_AES_STATUS:     rd_mux_data = {20'd0, i_aes_blocks_done, i_aes_error, i_aes_done, i_aes_busy};
            ADDR_VERSION:        rd_mux_data = VERSION_ID;
            ADDR_SYSTEM_CONTROL: rd_mux_data = {28'd0, pll_div_sel_reg, pll_enable_reg, mem_sel_aes_reg};
            ADDR_SYSTEM_STATUS:  rd_mux_data = {31'd0, i_pll_locked};
            default:             rd_mux_data = 32'h0000_0000;
        endcase
    end

    //-------------------------------------------------------------------------
    // Synchronous Write & Out-of-Frame Read Preload (always-on clk domain)
    // Uses synchronous reset for superior synthesis/STA QoR on SAED 32nm.
    //-------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            for (int i = 0; i < 4; i++) begin
                key_reg[i] <= 32'h0000_0000;
                iv_reg[i]  <= 32'h0000_0000;
            end
            counter_hi_reg      <= 32'h0000_0000;
            counter_lo_reg      <= 32'h0000_0000;
            num_blocks_reg      <= 32'h0000_0000;
            aes_mode_reg        <= 3'b000;
            aes_decrypt_reg     <= 1'b0;
            mem_sel_aes_reg     <= 1'b0;
            pll_enable_reg      <= 1'b0;
            pll_div_sel_reg     <= 2'b00;
            o_aes_start         <= 1'b0;
            csr_if.rd_data_hold <= 32'h0000_0000;
        end else begin
            // Write-one-pulse auto-clear
            o_aes_start <= 1'b0;

            if (csr_if.frame_valid && (csr_if.frame.addr != ADDR_NOP)) begin
                if (csr_if.frame.rwb) begin
                    // READ request (Transaction 1): latch selected CSR for Transaction 2
                    csr_if.rd_data_hold <= rd_mux_data;
                end else begin
                    // WRITE operation (Single Transaction)
                    case (csr_if.frame.addr)
                        ADDR_KEY0:       key_reg[0]      <= csr_if.frame.data;
                        ADDR_KEY1:       key_reg[1]      <= csr_if.frame.data;
                        ADDR_KEY2:       key_reg[2]      <= csr_if.frame.data;
                        ADDR_KEY3:       key_reg[3]      <= csr_if.frame.data;
                        ADDR_IV0:        iv_reg[0]       <= csr_if.frame.data;
                        ADDR_IV1:        iv_reg[1]       <= csr_if.frame.data;
                        ADDR_IV2:        iv_reg[2]       <= csr_if.frame.data;
                        ADDR_IV3:        iv_reg[3]       <= csr_if.frame.data;
                        ADDR_COUNTER_HI: counter_hi_reg  <= csr_if.frame.data;
                        ADDR_COUNTER_LO: counter_lo_reg  <= csr_if.frame.data;
                        ADDR_NUM_BLOCKS: num_blocks_reg  <= csr_if.frame.data;
                        ADDR_AES_CONTROL: begin
                            aes_mode_reg    <= csr_if.frame.data[4:2];
                            aes_decrypt_reg <= csr_if.frame.data[1];
                            o_aes_start     <= csr_if.frame.data[0];
                        end
                        ADDR_SYSTEM_CONTROL: begin
                            pll_div_sel_reg <= csr_if.frame.data[3:2];
                            pll_enable_reg  <= csr_if.frame.data[1];
                            mem_sel_aes_reg <= csr_if.frame.data[0];
                        end
                        // Read-only (0x0C, 0x0D, 0x0F) and unmapped addresses ignored
                        default: begin end
                    endcase
                end
            end
        end
    end

endmodule : minisoc_spi_csr

