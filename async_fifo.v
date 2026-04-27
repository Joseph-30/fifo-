// -----------------------------------------------------------
// File: async_fifo.v
// Description: Asynchronous FIFO (Cummings Architecture)
// Contains: Top wrapper, dual-port RAM, synchronizers, 
//           and empty/full logic.
// -----------------------------------------------------------

module async_fifo #(
    parameter DATASIZE = 8,
    parameter ADDRSIZE = 4  // FIFO depth = 2^ADDRSIZE = 16
)(
    input  wire                wclk, wrst_n, winc,
    input  wire [DATASIZE-1:0] wdata,
    output wire                wfull,
    
    input  wire                rclk, rrst_n, rinc,
    output wire [DATASIZE-1:0] rdata,
    output wire                rempty
);

    wire [ADDRSIZE-1:0] waddr, raddr;
    wire [ADDRSIZE:0]   wptr, rptr, wq2_rptr, rq2_wptr;

    // Dual-Port RAM
    fifomem #(DATASIZE, ADDRSIZE) mem (
        .wclk(wclk), .wclken(winc & ~wfull), .waddr(waddr), .wdata(wdata),
        .rclk(rclk), .raddr(raddr), .rdata(rdata)
    );

    // Read to Write Synchronizer
    sync_r2w #(ADDRSIZE) sync_r2w (
        .wclk(wclk), .wrst_n(wrst_n), .rptr(rptr), .wq2_rptr(wq2_rptr)
    );

    // Write to Read Synchronizer
    sync_w2r #(ADDRSIZE) sync_w2r (
        .rclk(rclk), .rrst_n(rrst_n), .wptr(wptr), .rq2_wptr(rq2_wptr)
    );

    // Write Logic
    wptr_full #(ADDRSIZE) wptr_logic (
        .wclk(wclk), .wrst_n(wrst_n), .winc(winc), .wq2_rptr(wq2_rptr),
        .wfull(wfull), .waddr(waddr), .wptr(wptr)
    );

    // Read Logic
    rptr_empty #(ADDRSIZE) rptr_logic (
        .rclk(rclk), .rrst_n(rrst_n), .rinc(rinc), .rq2_wptr(rq2_wptr),
        .rempty(rempty), .raddr(raddr), .rptr(rptr)
    );

endmodule


module fifomem #(
    parameter DATASIZE = 8,
    parameter ADDRSIZE = 4
)(
    input  wire                wclk, wclken,
    input  wire [ADDRSIZE-1:0] waddr, raddr,
    input  wire [DATASIZE-1:0] wdata,
    input  wire                rclk,
    output wire [DATASIZE-1:0] rdata
);
    localparam DEPTH = 1 << ADDRSIZE;
    reg [DATASIZE-1:0] mem [0:DEPTH-1];

    assign rdata = mem[raddr]; // Continuous assignment for fall-through

    always @(posedge wclk) begin
        if (wclken) mem[waddr] <= wdata;
    end
endmodule


module sync_r2w #(parameter ADDRSIZE = 4) (
    input  wire              wclk, wrst_n,
    input  wire [ADDRSIZE:0] rptr,
    output reg  [ADDRSIZE:0] wq2_rptr
);
    reg [ADDRSIZE:0] wq1_rptr;
    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) {wq2_rptr, wq1_rptr} <= 0;
        else         {wq2_rptr, wq1_rptr} <= {wq1_rptr, rptr};
    end
endmodule


module sync_w2r #(parameter ADDRSIZE = 4) (
    input  wire              rclk, rrst_n,
    input  wire [ADDRSIZE:0] wptr,
    output reg  [ADDRSIZE:0] rq2_wptr
);
    reg [ADDRSIZE:0] rq1_wptr;
    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) {rq2_wptr, rq1_wptr} <= 0;
        else         {rq2_wptr, rq1_wptr} <= {rq1_wptr, wptr};
    end
endmodule


module wptr_full #(parameter ADDRSIZE = 4) (
    input  wire              wclk, wrst_n, winc,
    input  wire [ADDRSIZE:0] wq2_rptr,
    output reg               wfull,
    output wire [ADDRSIZE-1:0] waddr,
    output reg  [ADDRSIZE:0] wptr
);
    reg  [ADDRSIZE:0] wbin;
    wire [ADDRSIZE:0] wgray_next, wbin_next;
    wire              wfull_val;

    // Memory write address pointer (binary)
    assign waddr = wbin[ADDRSIZE-1:0];

    // Binary and Gray pointer increments
    assign wbin_next  = wbin + (winc & ~wfull);
    assign wgray_next = (wbin_next >> 1) ^ wbin_next;

    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) {wbin, wptr} <= 0;
        else         {wbin, wptr} <= {wbin_next, wgray_next};
    end

    // Full calculation: Top two bits inverted, rest matching
    assign wfull_val = (wgray_next == {~wq2_rptr[ADDRSIZE:ADDRSIZE-1], wq2_rptr[ADDRSIZE-2:0]});

    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) wfull <= 1'b0;
        else         wfull <= wfull_val;
    end
endmodule


module rptr_empty #(parameter ADDRSIZE = 4) (
    input  wire              rclk, rrst_n, rinc,
    input  wire [ADDRSIZE:0] rq2_wptr,
    output reg               rempty,
    output wire [ADDRSIZE-1:0] raddr,
    output reg  [ADDRSIZE:0] rptr
);
    reg  [ADDRSIZE:0] rbin;
    wire [ADDRSIZE:0] rgray_next, rbin_next;
    wire              rempty_val;

    // Memory read address pointer (binary)
    assign raddr = rbin[ADDRSIZE-1:0];

    // Binary and Gray pointer increments
    assign rbin_next  = rbin + (rinc & ~rempty);
    assign rgray_next = (rbin_next >> 1) ^ rbin_next;

    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) {rbin, rptr} <= 0;
        else         {rbin, rptr} <= {rbin_next, rgray_next};
    end

    // Empty calculation: Pointers are exactly identical
    assign rempty_val = (rgray_next == rq2_wptr);

    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) rempty <= 1'b1;
        else         rempty <= rempty_val;
    end
endmodule