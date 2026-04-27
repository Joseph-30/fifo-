`timescale 1ns / 1ps

module tb_async_fifo;

    // Parameters
    parameter DATASIZE = 8;
    parameter ADDRSIZE = 4;

    // Testbench Signals
    reg  wclk, wrst_n, winc;
    reg  [DATASIZE-1:0] wdata;
    wire wfull;

    reg  rclk, rrst_n, rinc;
    wire [DATASIZE-1:0] rdata;
    wire rempty;

    // Instantiate the FIFO
    async_fifo #(
        .DATASIZE(DATASIZE),
        .ADDRSIZE(ADDRSIZE)
    ) dut (
        .wclk(wclk), .wrst_n(wrst_n), .winc(winc), .wdata(wdata), .wfull(wfull),
        .rclk(rclk), .rrst_n(rrst_n), .rinc(rinc), .rdata(rdata), .rempty(rempty)
    );

    // Clock Generation
    // Write clock: 10ns period (100 MHz)
    always #5 wclk = ~wclk; 
    
    // Read clock: 27ns period (~37 MHz) - Intentionally misaligned
    always #13.5 rclk = ~rclk; 

    // Waveform Dumping for GTKWave
    initial begin
        $dumpfile("fifo_waves.vcd");
        $dumpvars(0, tb_async_fifo);
    end

    // Stimulus Process
    initial begin
        // Initialize signals
        wclk = 0; wrst_n = 0; winc = 0; wdata = 0;
        rclk = 0; rrst_n = 0; rinc = 0;

        // Apply Reset
        #30;
        wrst_n = 1;
        rrst_n = 1;
        #30;

        // ---------------------------------------------------------
        // Test 1: Write until full
        // ---------------------------------------------------------
        $display("Starting Test 1: Write until full...");
        @(negedge wclk);
        while (!wfull) begin
            winc = 1;
            wdata = wdata + 1; // Write sequential data
            @(negedge wclk);
        end
        winc = 0;
        $display("FIFO is now FULL at time %0t", $time);

        // Wait a few clock cycles
        #100;

        // ---------------------------------------------------------
        // Test 2: Read until empty
        // ---------------------------------------------------------
        $display("Starting Test 2: Read until empty...");
        @(negedge rclk);
        while (!rempty) begin
            rinc = 1;
            @(negedge rclk);
            $display("Read Data: %h", rdata);
        end
        rinc = 0;
        $display("FIFO is now EMPTY at time %0t", $time);

        // Wait a few clock cycles
        #100;

        // ---------------------------------------------------------
        // Test 3: Concurrent Read and Write
        // ---------------------------------------------------------
        $display("Starting Test 3: Concurrent Read and Write...");
        @(negedge wclk);
        winc = 1;
        wdata = 8'hAA;
        
        #50; 
        @(negedge rclk);
        rinc = 1; // Turn on read while write is still happening

        #200;
        @(negedge wclk); winc = 0;
        @(negedge rclk); rinc = 0;

        $display("Simulation Complete.");
        $finish;
    end

endmodule