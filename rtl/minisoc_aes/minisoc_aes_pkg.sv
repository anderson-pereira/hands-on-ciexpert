//=============================================================================
// Project:     MiniSoC AES — RTL Design Track
// Package:     minisoc_aes_pkg
// Description: Common types, state-indexing helpers, and GF(2^8) finite-field
//              arithmetic functions for the AES-128 block cipher datapath
//              (NIST FIPS PUB 197, Sections 3.4, 4.2, 5.1.3, 5.3.3 &
//              DV_BlockGuide_MiniSoCAES_v1.0.0 Section 7.1).
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

    //-------------------------------------------------------------------------
    // GF(2^8) Multiplication Helpers modulo m(x) = x^8 + x^4 + x^3 + x + 1
    // Irreducible polynomial reduction byte: 8'h1b (FIPS-197 Section 4.2.1)
    //-------------------------------------------------------------------------

    // Multiply by {02} (xtime) in GF(2^8)
    function automatic logic [7:0] aes_xtime(input logic [7:0] b);
        begin
            aes_xtime = {b[6:0], 1'b0} ^ (b[7] ? 8'h1b : 8'h00);
        end
    endfunction

    // Multiply by {03} = {02} ^ {01} in GF(2^8)
    function automatic logic [7:0] aes_gf_mul3(input logic [7:0] b);
        begin
            aes_gf_mul3 = aes_xtime(b) ^ b;
        end
    endfunction

    // Multiply by {09} = {08} ^ {01} in GF(2^8)
    function automatic logic [7:0] aes_gf_mul9(input logic [7:0] b);
        logic [7:0] x2, x4, x8;
        begin
            x2          = aes_xtime(b);
            x4          = aes_xtime(x2);
            x8          = aes_xtime(x4);
            aes_gf_mul9 = x8 ^ b;
        end
    endfunction

    // Multiply by {0b} = {08} ^ {02} ^ {01} in GF(2^8)
    function automatic logic [7:0] aes_gf_mul11(input logic [7:0] b);
        logic [7:0] x2, x4, x8;
        begin
            x2           = aes_xtime(b);
            x4           = aes_xtime(x2);
            x8           = aes_xtime(x4);
            aes_gf_mul11 = x8 ^ x2 ^ b;
        end
    endfunction

    // Multiply by {0d} = {08} ^ {04} ^ {01} in GF(2^8)
    function automatic logic [7:0] aes_gf_mul13(input logic [7:0] b);
        logic [7:0] x2, x4, x8;
        begin
            x2           = aes_xtime(b);
            x4           = aes_xtime(x2);
            x8           = aes_xtime(x4);
            aes_gf_mul13 = x8 ^ x4 ^ b;
        end
    endfunction

    // Multiply by {0e} = {08} ^ {04} ^ {02} in GF(2^8)
    function automatic logic [7:0] aes_gf_mul14(input logic [7:0] b);
        logic [7:0] x2, x4, x8;
        begin
            x2           = aes_xtime(b);
            x4           = aes_xtime(x2);
            x8           = aes_xtime(x4);
            aes_gf_mul14 = x8 ^ x4 ^ x2;
        end
    endfunction

endpackage : minisoc_aes_pkg
