`timescale 1ns/1ps

module tb_top;

    logic clk;
    logic rst_n;
    logic d;
    logic q;

    top dut (
        .clk(clk),
        .rst_n(rst_n),
        .d(d),
        .q(q)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        rst_n = 0;
        d = 0;
        #15 rst_n = 1;
        #10 d = 1;
        #20 d = 0;
        #50 $display("Hello World! Simulation finished successfully.");
        $finish;
    end
    
    initial begin
        $monitor("Time=%0t | clk=%b | rst_n=%b | d=%b | q=%b", $time, clk, rst_n, d, q);
    end

endmodule
