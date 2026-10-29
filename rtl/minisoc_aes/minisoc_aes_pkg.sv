//=============================================================================
// Project:     MiniSoC AES — RTL Design Track
// Package:     minisoc_aes_pkg
// Description: Common types and state-indexing helpers for the AES-128 block
//              cipher datapath (FIPS PUB 197, Section 3.4 & Block Guide 7.1).
//
// State Bit-Ordering Convention (128-bit vector):
//   - Byte 0 is [127:120], ..., Byte 15 is [7:0].
//   - Word 0 (Column 0) is [127:96], ..., Word 3 (Column 3) is [31:0].
//   - Byte n (0..15) maps to FIPS-197 s[r][c] with r = n mod 4, c = n div 4.
//   - Consequently, in the 2D packed type aes_state_t, the outer dimension
//     indexes the column c (0..3) and the inner dimension indexes row r (0..3):
//       state_mat[c][r] <==> FIPS-197 s[r, c]
//=============================================================================

package minisoc_aes_pkg;

    // Column-major 4x4 byte matrix: state[c][r] == byte (4*c + r)
    typedef logic [0:3][0:3][7:0] aes_state_t;

    // Extract byte s[r, c] using mathematical FIPS-197 (row, col) order
    function automatic logic [7:0] aes_get_byte(
        input logic [127:0] state,
        input logic [1:0]   r,
        input logic [1:0]   c
    );
        aes_state_t mat;
        begin
            mat          = aes_state_t'(state);
            aes_get_byte = mat[c][r];
        end
    endfunction

endpackage : minisoc_aes_pkg
