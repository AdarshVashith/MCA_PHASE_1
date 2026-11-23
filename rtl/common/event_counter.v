`default_nettype none
`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// event_counter : counts the cycles in which 'ev' is high
//   Same freeze rule as perf_counters: the cycle in which halt first goes high
//   is still counted, then the counter freezes. Used for the Phase II memory
//   hierarchy statistics (misses, stall cycles, arbitration conflicts).
// -----------------------------------------------------------------------------
module event_counter (
    input  wire        clk,
    input  wire        rst,
    input  wire        halt,
    input  wire        ev,
    output reg  [31:0] count
);
    reg stopped;

    always @(posedge clk) begin
        if (rst) begin
            stopped <= 1'b0;
            count   <= 32'd0;
        end else if (!stopped) begin
            if (ev)   count   <= count + 32'd1;
            if (halt) stopped <= 1'b1;
        end
    end
endmodule
`default_nettype wire
