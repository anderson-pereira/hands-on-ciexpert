//=============================================================================
// Project:     MiniSoC AES — RTL Design Track
// Module:      minisoc_memory
// Description: Shared physical single-port synchronous SRAM model (1024 x 32b)
//              aligned with Section 7 of DV_BlockGuide_MiniSoCAES_v1.0.0:
//              - Capacity: 1024 words x 32 bits (up to 256 AES 128-bit blocks).
//              - i_wr_en = 1: synchronous write of i_data to mem[i_addr].
//              - i_wr_en = 0: synchronous read of mem[i_addr] into o_data.
//              - No functional reset on the memory array (Section 3 & 7.3).
//=============================================================================

module minisoc_memory #(
    parameter int unsigned ADDR_WIDTH = 10,
    parameter int unsigned DATA_WIDTH = 32,
    parameter int unsigned DEPTH      = 1024
) (
    input  logic                  i_clk,
    input  logic                  i_wr_en,
    input  logic [ADDR_WIDTH-1:0] i_addr,
    input  logic [DATA_WIDTH-1:0] i_data,
    output logic [DATA_WIDTH-1:0] o_data
);

    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    always_ff @(posedge i_clk) begin
        if (i_wr_en) begin
            mem[i_addr] <= i_data;
        end else begin
            o_data <= mem[i_addr];
        end
    end

endmodule : minisoc_memory

