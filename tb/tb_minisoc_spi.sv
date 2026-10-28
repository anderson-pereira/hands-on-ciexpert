//=============================================================================
// Project:     MiniSoC AES — RTL Design Track
// Testbench:   tb_minisoc_spi
// Description: Directed self-checking testbench validating the redesigned
//              minisoc_spi subsystem (40-bit Out-of-Frame SPI Mode 0, 2-frame
//              read & pipelined read, 32-bit CSR bank in 2 GHz always-on clk),
//              integrated with minisoc_pll_mock (bootstrap & dividers) and
//              minisoc_memory (ownership arbitration via MEM_SEL_AES).
//=============================================================================

`timescale 1ns/1ps

module tb_minisoc_spi;
    import minisoc_spi_pkg::*;

    //-------------------------------------------------------------------------
    // Clocks & Reset (2 GHz ref clk, up to 25 MHz spi_sclk, 200 MHz mem_clk)
    //-------------------------------------------------------------------------
    logic clk      = 1'b0;
    logic rst_n    = 1'b0;
    logic spi_sclk = 1'b0;
    logic spi_cs_n = 1'b1;
    logic spi_mosi = 1'b0;
    wire  spi_miso;

    logic        mem_clk     = 1'b0;
    logic [31:0] mem_i_data  = 32'd0;
    logic        mem_i_wr_en = 1'b0;
    logic [9:0]  mem_i_addr  = 10'd0;
    wire  [31:0] mem_o_data;

    // 2.000 GHz always-on reference clock (T = 0.5 ns = 500 ps)
    always #0.25 clk = ~clk;

    // 200 MHz external MEMORY DATA clock (T = 5.0 ns)
    always #2.5 mem_clk = ~mem_clk;

    //-------------------------------------------------------------------------
    // Interconnect Signals (SPI <-> PLL <-> Memory <-> Mocked AES Status)
    //-------------------------------------------------------------------------
    wire [127:0] cfg_key;
    wire [127:0] cfg_iv;
    wire [63:0]  cfg_counter;
    wire [31:0]  cfg_num_blocks;
    wire [2:0]   cfg_mode;
    wire         cfg_decrypt;
    wire         aes_start;

    logic        aes_busy        = 1'b0;
    logic        aes_done        = 1'b0;
    logic        aes_error       = 1'b0;
    logic [8:0]  aes_blocks_done = 9'd0;

    wire         mem_sel_aes;
    wire         pll_enable;
    wire [1:0]   pll_div_sel;
    wire         pll_locked;
    wire         sys_clk;

    // Simulated AES-side memory port signals (for ownership mux verification)
    logic        aes_mem_wr_en = 1'b0;
    logic [9:0]  aes_mem_addr  = 10'd0;
    logic [31:0] aes_mem_wdata = 32'd0;

    // Start pulse counter in always-on clk domain (synchronous reset)
    int unsigned start_pulse_cnt;
    always_ff @(posedge clk) begin
        if (!rst_n) start_pulse_cnt <= 0;
        else if (aes_start) start_pulse_cnt <= start_pulse_cnt + 1;
    end

    // Monitor active sys_clk edges post-reset to verify PLL clock release / gating
    int unsigned sys_clk_edges = 0;
    always @(posedge sys_clk) begin
        if (rst_n) sys_clk_edges <= sys_clk_edges + 1;
    end

    //-------------------------------------------------------------------------
    // DUT Instantiations: SPI + PLL Mock + Shared Memory Mux
    //-------------------------------------------------------------------------
    minisoc_spi u_spi (
        .clk               (clk),
        .rst_n             (rst_n),
        .spi_sclk          (spi_sclk),
        .spi_cs_n          (spi_cs_n),
        .spi_mosi          (spi_mosi),
        .spi_miso          (spi_miso),
        .o_cfg_key         (cfg_key),
        .o_cfg_iv          (cfg_iv),
        .o_cfg_counter     (cfg_counter),
        .o_cfg_num_blocks  (cfg_num_blocks),
        .o_cfg_mode        (cfg_mode),
        .o_cfg_decrypt     (cfg_decrypt),
        .o_aes_start       (aes_start),
        .i_aes_busy        (aes_busy),
        .i_aes_done        (aes_done),
        .i_aes_error       (aes_error),
        .i_aes_blocks_done (aes_blocks_done),
        .o_mem_sel_aes     (mem_sel_aes),
        .o_pll_enable      (pll_enable),
        .o_pll_div_sel     (pll_div_sel),
        .i_pll_locked      (pll_locked)
    );

    minisoc_pll_mock u_pll (
        .i_clk     (clk),
        .i_rst_n   (rst_n),
        .i_enable  (pll_enable),
        .i_div_sel (pll_div_sel),
        .o_sys_clk (sys_clk),
        .o_locked  (pll_locked)
    );

    // Memory ownership mux (Section 7.2: 0 = MEMORY DATA IF, 1 = AES Engine)
    wire        mux_mem_clk   = mem_sel_aes ? sys_clk       : mem_clk;
    wire        mux_mem_wr_en = mem_sel_aes ? aes_mem_wr_en : mem_i_wr_en;
    wire [9:0]  mux_mem_addr  = mem_sel_aes ? aes_mem_addr  : mem_i_addr;
    wire [31:0] mux_mem_wdata = mem_sel_aes ? aes_mem_wdata : mem_i_data;

    minisoc_memory u_mem (
        .i_clk   (mux_mem_clk),
        .i_wr_en (mux_mem_wr_en),
        .i_addr  (mux_mem_addr),
        .i_data  (mux_mem_wdata),
        .o_data  (mem_o_data)
    );

    //-------------------------------------------------------------------------
    // SPI Master BFM Tasks (Mode 0, MSB-first, 25 MHz SCLK -> T = 40 ns)
    //-------------------------------------------------------------------------
    // Raw 40-bit shift without touching spi_cs_n (enables continuous CS_n=0 streaming)
    task automatic spi_shift_40b_no_cs(
        input  logic        rwb,
        input  logic [5:0]  addr,
        input  logic [31:0] tx_data,
        output logic [39:0] rx_raw
    );
        logic [39:0] tx_raw;
        begin
            tx_raw = {rwb, addr, 1'b0, tx_data};
            rx_raw = 40'd0;
            for (int b = 39; b >= 0; b--) begin
                spi_mosi = tx_raw[b];
                #20 spi_sclk = 1'b1; // Setup before posedge (25 MHz -> 20 ns half-period)
                rx_raw[b] = spi_miso;
                #20 spi_sclk = 1'b0;
            end
        end
    endtask

    task automatic spi_transfer_frame(
        input  logic        rwb,
        input  logic [5:0]  addr,
        input  logic [31:0] tx_data,
        output logic [39:0] rx_raw
    );
        begin
            spi_sclk = 1'b0;
            #20 spi_cs_n = 1'b0;
            spi_shift_40b_no_cs(rwb, addr, tx_data, rx_raw);
            #20 spi_cs_n = 1'b1;
            spi_mosi = 1'b0;
            #40 begin end // Inter-transaction CS_n high time
        end
    endtask

    // Write CSR: 1 SPI transaction (40 bits)
    task automatic spi_write(input logic [5:0] addr, input logic [31:0] data);
        logic [39:0] unused_rx;
        begin
            spi_transfer_frame(1'b0, addr, data, unused_rx);
        end
    endtask

    // Read CSR: 2 SPI transactions (Transaction 1 = READ req, Transaction 2 = NOP 0x3F)
    task automatic spi_read(input logic [5:0] addr, output logic [31:0] rdata);
        logic [39:0] rx_req, rx_ret;
        begin
            spi_transfer_frame(1'b1, addr,     32'h0000_0000, rx_req);
            spi_transfer_frame(1'b0, ADDR_NOP, 32'h0000_0000, rx_ret);
            if (rx_ret[39:32] !== 8'h00) begin
                $fatal(1, "[TB ERROR] Non-zero MISO header during read return: 0x%02h", rx_ret[39:32]);
            end
            rdata = rx_ret[31:0];
        end
    endtask

    // External MEMORY DATA write/read helpers
    task automatic ext_mem_write(input logic [9:0] addr, input logic [31:0] data);
        begin
            @(negedge mem_clk) begin
                mem_i_wr_en = 1'b1;
                mem_i_addr  = addr;
                mem_i_data  = data;
            end
            @(negedge mem_clk) mem_i_wr_en = 1'b0;
        end
    endtask

    task automatic ext_mem_read(input logic [9:0] addr, output logic [31:0] data);
        begin
            @(negedge mem_clk) begin
                mem_i_wr_en = 1'b0;
                mem_i_addr  = addr;
            end
            @(posedge mem_clk) begin end
            #1 data = mem_o_data;
        end
    endtask

    //-------------------------------------------------------------------------
    // Main Verification Sequence
    //-------------------------------------------------------------------------
    logic [31:0] rdata;
    logic [39:0] pipe_rx;

    initial begin
        rst_n = 1'b0;
        #20 rst_n = 1'b1;
        #20 begin end

        //=====================================================================
        // 1. Bootstrap Rule Check: SPI operates while PLL is OFF (sys_clk = 0)
        //=====================================================================
        if (pll_locked !== 1'b0 || sys_clk_edges != 0) begin
            $fatal(1, "[TB ERROR] PLL should start disabled and unlocked!");
        end

        spi_read(ADDR_VERSION, rdata);
        if (rdata !== SPI_FRONTEND_VERSION) begin
            $fatal(1, "[TB ERROR] VERSION mismatch: got 0x%08h, expected 0x%08h", rdata, SPI_FRONTEND_VERSION);
        end
        $display("[TB] 1. Bootstrap read of VERSION (0x%08h) succeeded with PLL disabled!", rdata);

        //=====================================================================
        // 2. Full 32-bit CSR Read/Write: KEY0..3, IV0..3, COUNTER, NUM_BLOCKS
        //=====================================================================
        spi_write(ADDR_KEY0, 32'h2B7E_1516);
        spi_write(ADDR_KEY1, 32'h28AE_D2A6);
        spi_write(ADDR_KEY2, 32'hABF7_1588);
        spi_write(ADDR_KEY3, 32'h09CF_4F3C);

        spi_write(ADDR_IV0,  32'h0001_0203);
        spi_write(ADDR_IV1,  32'h0405_0607);
        spi_write(ADDR_IV2,  32'h0809_0A0B);
        spi_write(ADDR_IV3,  32'h0C0D_0E0F);

        spi_write(ADDR_COUNTER_HI, 32'hCAFE_BABE);
        spi_write(ADDR_COUNTER_LO, 32'hDEAD_BEEF);
        spi_write(ADDR_NUM_BLOCKS, 32'd256); // Max block count supported (req 1..256)

        if (cfg_key !== 128'h2B7E1516_28AED2A6_ABF71588_09CF4F3C)
            $fatal(1, "[TB ERROR] cfg_key mismatch: 0x%032h", cfg_key);
        if (cfg_iv !== 128'h00010203_04050607_08090A0B_0C0D0E0F)
            $fatal(1, "[TB ERROR] cfg_iv mismatch: 0x%032h", cfg_iv);
        if (cfg_counter !== 64'hCAFEBABE_DEADBEEF)
            $fatal(1, "[TB ERROR] cfg_counter mismatch: 0x%016h", cfg_counter);
        if (cfg_num_blocks !== 32'd256)
            $fatal(1, "[TB ERROR] cfg_num_blocks mismatch: %0d", cfg_num_blocks);

        // Verify Pipelined Back-to-Back Reads across KEY0..KEY3 + final NOP
        spi_transfer_frame(1'b1, ADDR_KEY0, 32'd0, pipe_rx); // Req KEY0
        spi_transfer_frame(1'b1, ADDR_KEY1, 32'd0, pipe_rx); // Ret KEY0, Req KEY1
        if (pipe_rx[31:0] !== 32'h2B7E_1516) $fatal(1, "[TB ERROR] Pipelined KEY0 read failed: 0x%08h", pipe_rx[31:0]);
        spi_transfer_frame(1'b1, ADDR_KEY2, 32'd0, pipe_rx); // Ret KEY1, Req KEY2
        if (pipe_rx[31:0] !== 32'h28AE_D2A6) $fatal(1, "[TB ERROR] Pipelined KEY1 read failed: 0x%08h", pipe_rx[31:0]);
        spi_transfer_frame(1'b1, ADDR_KEY3, 32'd0, pipe_rx); // Ret KEY2, Req KEY3
        if (pipe_rx[31:0] !== 32'hABF7_1588) $fatal(1, "[TB ERROR] Pipelined KEY2 read failed: 0x%08h", pipe_rx[31:0]);
        spi_transfer_frame(1'b0, ADDR_NOP,  32'd0, pipe_rx); // Ret KEY3, NOP
        if (pipe_rx[31:0] !== 32'h09CF_4F3C) $fatal(1, "[TB ERROR] Pipelined KEY3 read failed: 0x%08h", pipe_rx[31:0]);
        $display("[TB] 2. 128-bit KEY/IV, 64-bit COUNTER, NUM_BLOCKS=256, and pipelined reads verified!");

        //=====================================================================
        // 3. External Memory Write/Read (MEM_SEL_AES = 0, Section 7)
        //=====================================================================
        ext_mem_write(10'd0, 32'h0011_2233);
        ext_mem_write(10'd1, 32'h4455_6677);
        ext_mem_write(10'd2, 32'h8899_AABB);
        ext_mem_write(10'd3, 32'hCCDD_EEFF);

        ext_mem_read(10'd0, rdata);
        if (rdata !== 32'h0011_2233) $fatal(1, "[TB ERROR] mem[0] mismatch: 0x%08h", rdata);
        ext_mem_read(10'd3, rdata);
        if (rdata !== 32'hCCDD_EEFF) $fatal(1, "[TB ERROR] mem[3] mismatch: 0x%08h", rdata);
        $display("[TB] 3. External MEMORY DATA 1024x32 write/read verified!");

        //=====================================================================
        // 4. PLL Configuration & Lock Acquisition (Programming Model Steps 8-9)
        //=====================================================================
        // Configure PLL_DIV_SEL = /4 (2'b10), PLL_ENABLE = 1, MEM_SEL_AES = 0 -> 4'b1010 = 0xA
        spi_write(ADDR_SYSTEM_CONTROL, 32'h0000_000A);
        spi_read(ADDR_SYSTEM_STATUS, rdata);
        if (rdata[0] !== 1'b1) begin
            $fatal(1, "[TB ERROR] Expected PLL_LOCKED == 1 after SPI transaction time, got 0x%08h", rdata);
        end
        if (sys_clk_edges == 0) begin
            $fatal(1, "[TB ERROR] sys_clk did not oscillate after PLL_LOCKED == 1!");
        end
        $display("[TB] 4. PLL enabled via SPI while unlocked, locked cleanly, sys_clk active (%0d edges)!", sys_clk_edges);

        //=====================================================================
        // 5. Memory Ownership Handover, AES_CONTROL W1P START, and AES_STATUS
        //=====================================================================
        // Step 7: Program MODE = CTR (3'b101), DECRYPT = 0, START = 0 -> {3'b101, 1'b0, 1'b0} = 5'b10100 = 0x14
        spi_write(ADDR_AES_CONTROL, 32'h0000_0014);
        // Step 10: Hand memory to AES (MEM_SEL_AES = 1, PLL_ENABLE = 1, DIV = /4) -> 0xB
        spi_write(ADDR_SYSTEM_CONTROL, 32'h0000_000B);
        if (mem_sel_aes !== 1'b1) $fatal(1, "[TB ERROR] MEM_SEL_AES failed to assert!");

        // Step 11: Write START = 1 along with MODE = CTR, DECRYPT = 0 -> 0x15
        spi_write(ADDR_AES_CONTROL, 32'h0000_0015);
        if (start_pulse_cnt != 1) begin
            $fatal(1, "[TB ERROR] Expected exactly 1 o_aes_start pulse, saw %0d", start_pulse_cnt);
        end

        // START bit must auto-clear to 0 on readback, retaining MODE and DECRYPT (0x14)
        spi_read(ADDR_AES_CONTROL, rdata);
        if (rdata !== 32'h0000_0014) begin
            $fatal(1, "[TB ERROR] AES_CONTROL readback mismatch (START must read 0): 0x%08h", rdata);
        end

        // Simulate AES completion of 256 blocks
        aes_busy        = 1'b0;
        aes_done        = 1'b1;
        aes_error       = 1'b0;
        aes_blocks_done = 9'd256;

        spi_read(ADDR_AES_STATUS, rdata);
        if (rdata !== {20'd0, 9'd256, 1'b0, 1'b1, 1'b0}) begin
            $fatal(1, "[TB ERROR] AES_STATUS mismatch: got 0x%08h", rdata);
        end
        $display("[TB] 5. Memory ownership handover, W1P START pulse, and AES_STATUS (BLOCKS_DONE=256) verified!");

        //=====================================================================
        // 6. Read-Only Protection, NOP Immunity, and Aborted (<40-bit) Frame
        //=====================================================================
        spi_write(ADDR_VERSION,    32'hFFFF_FFFF);
        spi_write(ADDR_AES_STATUS, 32'hFFFF_FFFF);
        spi_write(ADDR_NOP,        32'hFFFF_FFFF);

        spi_read(ADDR_VERSION, rdata);
        if (rdata !== SPI_FRONTEND_VERSION) $fatal(1, "[TB ERROR] RO VERSION overwritten!");

        // Send an aborted 17-bit runt frame attempting to overwrite KEY0
        spi_cs_n = 1'b0;
        for (int b = 0; b < 17; b++) begin
            spi_mosi = 1'b1;
            #20 spi_sclk = 1'b1;
            #20 spi_sclk = 1'b0;
        end
        #20 spi_cs_n = 1'b1;
        #40 begin end

        spi_read(ADDR_KEY0, rdata);
        if (rdata !== 32'h2B7E_1516) begin
            $fatal(1, "[TB ERROR] Aborted runt frame corrupted KEY0: 0x%08h", rdata);
        end
        $display("[TB] 6. Read-Only protection, NOP immunity, and runt-frame abort safety verified!");

        //=====================================================================
        // 7. Continuous Multi-Frame Streaming with spi_cs_n Held Low (CS_n=0)
        //=====================================================================
        // 7a. 80 continuous SCLK pulses: Frame 1 = READ VERSION, Frame 2 = NOP
        spi_sclk = 1'b0;
        #20 spi_cs_n = 1'b0;
        spi_shift_40b_no_cs(1'b1, ADDR_VERSION, 32'd0, pipe_rx); // Clocks 1..40
        spi_shift_40b_no_cs(1'b0, ADDR_NOP,     32'd0, pipe_rx); // Clocks 41..80
        #20 spi_cs_n = 1'b1;
        spi_mosi = 1'b0;
        #40 begin end

        if (pipe_rx !== {8'h00, SPI_FRONTEND_VERSION}) begin
            $fatal(1, "[TB ERROR] Continuous 80-clk read failed: got 0x%010h", pipe_rx);
        end

        // 7b. 5 continuous 40-bit frames (2 Writes + 2 Pipelined Reads + NOP)
        //     followed by a 13-bit aborted runt tail in a single CS_n=0 window
        #20 spi_cs_n = 1'b0;
        spi_shift_40b_no_cs(1'b0, ADDR_COUNTER_HI, 32'h1357_9BDF, pipe_rx); // F1: Write HI
        spi_shift_40b_no_cs(1'b0, ADDR_COUNTER_LO, 32'h2468_ACE0, pipe_rx); // F2: Write LO
        spi_shift_40b_no_cs(1'b1, ADDR_COUNTER_HI, 32'd0,         pipe_rx); // F3: Req HI
        spi_shift_40b_no_cs(1'b1, ADDR_COUNTER_LO, 32'd0,         pipe_rx); // F4: Ret HI, Req LO
        if (pipe_rx !== {8'h00, 32'h1357_9BDF}) begin
            $fatal(1, "[TB ERROR] Continuous pipelined COUNTER_HI mismatch: 0x%010h", pipe_rx);
        end
        spi_shift_40b_no_cs(1'b0, ADDR_NOP,        32'd0,         pipe_rx); // F5: Ret LO, NOP
        if (pipe_rx !== {8'h00, 32'h2468_ACE0}) begin
            $fatal(1, "[TB ERROR] Continuous pipelined COUNTER_LO mismatch: 0x%010h", pipe_rx);
        end
        // Trailing 13-bit incomplete frame (must be discarded when CS_n rises)
        for (int b = 0; b < 13; b++) begin
            spi_mosi = (b == 0) ? 1'b0 : 1'b1;
            #20 spi_sclk = 1'b1;
            #20 spi_sclk = 1'b0;
        end
        #20 spi_cs_n = 1'b1;
        spi_mosi = 1'b0;
        #40 begin end

        if (cfg_counter !== 64'h13579BDF_2468ACE0) begin
            $fatal(1, "[TB ERROR] Continuous CS_n=0 cfg_counter corrupted: 0x%016h", cfg_counter);
        end
        $display("[TB] 7. Continuous spi_cs_n=0 streaming (80-clk read & 5-frame pipeline + runt abort) verified!");

        //=====================================================================
        // 8. Deselected Bus Traffic Immunity (40/80 Clocks with spi_cs_n = 1)
        //=====================================================================
        // Arm rd_data_hold with KEY0 (0x2B7E_1516) via a valid READ request
        spi_transfer_frame(1'b1, ADDR_KEY0, 32'd0, pipe_rx);

        // 8a. 40-clock WRITE while spi_cs_n = 1 (must NOT overwrite KEY0 or drive MISO)
        spi_cs_n = 1'b1;
        spi_shift_40b_no_cs(1'b0, ADDR_KEY0, 32'hDEAD_DEAD, pipe_rx);
        if (pipe_rx !== 40'd0) begin
            $fatal(1, "[TB ERROR] MISO driven while spi_cs_n=1 during write traffic: 0x%010h", pipe_rx);
        end

        // 8b. 80-clock READ + NOP while spi_cs_n = 1 (must keep MISO=0 and preserve rd_data_hold)
        spi_shift_40b_no_cs(1'b1, ADDR_VERSION, 32'd0, pipe_rx);
        if (pipe_rx !== 40'd0) begin
            $fatal(1, "[TB ERROR] MISO driven while spi_cs_n=1 during read req: 0x%010h", pipe_rx);
        end
        spi_shift_40b_no_cs(1'b0, ADDR_NOP,     32'd0, pipe_rx);
        if (pipe_rx !== 40'd0) begin
            $fatal(1, "[TB ERROR] MISO driven while spi_cs_n=1 during read return: 0x%010h", pipe_rx);
        end
        spi_mosi = 1'b0;
        #40 begin end

        // Verify previously armed KEY0 readback is still intact on next selected NOP
        spi_transfer_frame(1'b0, ADDR_NOP, 32'd0, pipe_rx);
        if (pipe_rx !== {8'h00, 32'h2B7E_1516} || cfg_key[127:96] !== 32'h2B7E_1516) begin
            $fatal(1, "[TB ERROR] Deselected traffic corrupted KEY0 or rd_data_hold: rx=0x%010h key0=0x%08h",
                   pipe_rx, cfg_key[127:96]);
        end
        $display("[TB] 8. Deselected bus immunity (40-clk write & 80-clk read with spi_cs_n=1) verified!");

        $display("===================================================================");
        $display("PASS: All MiniSoC SPI, CDC, 32-bit CSR, PLL Bootstrap, and Memory");
        $display("      Arbitration checks passed in compliance with Block Guide v1.0!");
        $display("===================================================================");
        $finish;
    end

    initial begin
        #500000 $fatal(1, "[TB TIMEOUT] Simulation exceeded watchdog limit!");
    end

endmodule : tb_minisoc_spi
