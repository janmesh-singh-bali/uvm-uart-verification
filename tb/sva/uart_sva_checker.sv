//======================================================================
// uart_sva_checker.sv
//----------------------------------------------------------------------
// Assertion-based checker for the parameterized UART TX/RX loopback DUT.
//
//   7 concurrent assertions : start-bit timing, per-bit stability
//                             against CLKS_PER_BIT, stop-bit and idle
//                             framing, frame-overlap protection, and
//                             the o_Tx_Done handshake pulse width.
//   5 cover properties      : payload corner cases (0x00 / 0xFF),
//                             back-to-back burst traffic, long idle
//                             hold, completed RX frame.
//
// PORTABILITY NOTE
//   Deliberately restricted to the SVA subset that elaborates on both
//   simulators used by this project.  In particular there are no ##N
//   cycle delays anywhere: the open-source flow rejects "## (in
//   sequence expression)" outright, so every multi-cycle relationship
//   is expressed with $past() or with an explicit FSM-state guard.
//   Also avoided: [*N] repetition, unbounded ranges, local variables,
//   throughout / within / intersect.
//
// Bound into uart_top -- see uart_sva_bind.sv
//======================================================================
`ifndef UART_SVA_CHECKER_SV
`define UART_SVA_CHECKER_SV

module uart_sva_checker #(
    parameter int CLKS_PER_BIT = 868
) (
    input logic                            clk,

    // DUT boundary
    input logic                            tx_dv,
    input logic [7:0]                      tx_byte,
    input logic                            tx_active,
    input logic                            tx_done,
    input logic                            tx_serial,   // internal loopback wire
    input logic                            rx_dv,
    input logic [7:0]                      rx_byte,

    // TX FSM white-box taps (hierarchical, connected in the bind)
    input logic [2:0]                      tx_state,
    input logic [$clog2(CLKS_PER_BIT)-1:0] tx_clk_cnt,
    input logic [7:0]                      tx_data_lat
);

  //--------------------------------------------------------------------
  // Mirror of the TX FSM encoding (uart_tx.v)
  //--------------------------------------------------------------------
  localparam logic [2:0] S_IDLE    = 3'b000;
  localparam logic [2:0] S_START   = 3'b001;
  localparam logic [2:0] S_DATA    = 3'b010;
  localparam logic [2:0] S_STOP    = 3'b011;
  localparam logic [2:0] S_CLEANUP = 3'b100;

  //--------------------------------------------------------------------
  // Idle-gap counter.
  // Counts clocks since the transmitter last went idle.  The cover
  // properties use it to tell burst traffic (delay == 0) apart from the
  // long-hold stress case (delay == 1000) without needing unbounded
  // sequence ranges.
  //--------------------------------------------------------------------
  logic [31:0] idle_cnt = 32'd0;

  always @(posedge clk) begin
    if (tx_active) idle_cnt <= 32'd0;
    else if (idle_cnt != 32'hFFFF_FFFF) idle_cnt <= idle_cnt + 32'd1;
  end

  //====================================================================
  // ASSERTIONS
  //====================================================================

  //--------------------------------------------------------------------
  // A1 - Start bit is driven low.
  // tx_active rises one clock after i_Tx_DV is sampled in s_IDLE; the
  // s_TX_START_BIT assignment o_Tx_Serial <= 1'b0 lands one clock after
  // that, hence |=> from the rise of tx_active.
  //--------------------------------------------------------------------
  property p_start_bit_low;
    @(posedge clk) $rose(tx_active) |=> (tx_serial == 1'b0);
  endproperty
  a_start_bit_low : assert property (p_start_bit_low)
    else $error("SVA A1: start bit not driven low after tx_active asserted");

  //--------------------------------------------------------------------
  // A2 - Start bit occupies a full CLKS_PER_BIT baud period.
  // The FSM may not leave s_TX_START_BIT until r_Clock_Count has
  // counted all the way to CLKS_PER_BIT-1.  Leaving early would mean a
  // short start bit and a baud-rate mismatch at the receiver.
  //--------------------------------------------------------------------
  property p_start_bit_duration;
    @(posedge clk) ((tx_state == S_START) && (tx_clk_cnt < CLKS_PER_BIT - 1))
                   |=> (tx_state == S_START);
  endproperty
  a_start_bit_duration : assert property (p_start_bit_duration)
    else $error("SVA A2: start bit terminated before CLKS_PER_BIT=%0d clocks", CLKS_PER_BIT);

  //--------------------------------------------------------------------
  // A3 - Per-bit stability against CLKS_PER_BIT.
  // In s_TX_DATA_BITS the serial line may only change on the clock
  // after r_Clock_Count wraps to 0.  For every other count value the
  // line must hold, which is what proves each data bit occupies exactly
  // one full baud period.
  //--------------------------------------------------------------------
  property p_tx_bit_stable;
    @(posedge clk) ((tx_state == S_DATA) && (tx_clk_cnt != 0)) |=> $stable(tx_serial);
  endproperty
  a_tx_bit_stable : assert property (p_tx_bit_stable)
    else $error("SVA A3: serial line changed mid-bit (per-bit stability violated)");

  //--------------------------------------------------------------------
  // A4 - Stop bit is high for the whole stop-bit period.
  // o_Tx_Serial <= 1'b1 is issued on the first s_TX_STOP_BIT clock, so
  // the line is guaranteed high from count 1 onward.
  //--------------------------------------------------------------------
  property p_stop_bit_high;
    @(posedge clk) ((tx_state == S_STOP) && (tx_clk_cnt > 0)) |-> (tx_serial == 1'b1);
  endproperty
  a_stop_bit_high : assert property (p_stop_bit_high)
    else $error("SVA A4: stop bit not held high");

  //--------------------------------------------------------------------
  // A5 - Line idles high between frames (mark state).
  //--------------------------------------------------------------------
  property p_line_idle_high;
    @(posedge clk) (tx_state == S_IDLE) |=> (tx_serial == 1'b1);
  endproperty
  a_line_idle_high : assert property (p_line_idle_high)
    else $error("SVA A5: serial line not idling high");

  //--------------------------------------------------------------------
  // A6 - Frame-overlap protection.
  // r_Tx_Data is latched on the s_IDLE -> s_TX_START_BIT transition.  A
  // second i_Tx_DV asserted while a frame is in flight must not be able
  // to overwrite the payload mid-frame.  This is the assertion that
  // catches a driver issuing back-to-back bytes too aggressively.
  //--------------------------------------------------------------------
  property p_no_frame_overlap;
    @(posedge clk) tx_active |=> $stable(tx_data_lat);
  endproperty
  a_no_frame_overlap : assert property (p_no_frame_overlap)
    else $error("SVA A6: latched TX payload changed mid-frame (frame overlap)");

  //--------------------------------------------------------------------
  // A7 - o_Tx_Done handshake pulse is exactly two clocks wide.
  // The nandland header comment claims a one-clock pulse, but the RTL
  // sets r_Tx_Done in BOTH the last s_TX_STOP_BIT clock and s_CLEANUP,
  // and only clears it back in s_IDLE.  Expressed with $past so no ##
  // cycle delay is needed.
  //--------------------------------------------------------------------
  property p_tx_done_pulse;
    @(posedge clk) $fell(tx_done) |-> ($past(tx_done, 1) == 1'b1)
                                   && ($past(tx_done, 2) == 1'b1)
                                   && ($past(tx_done, 3) == 1'b0);
  endproperty
  a_tx_done_pulse : assert property (p_tx_done_pulse)
    else $error("SVA A7: o_Tx_Done pulse is not exactly 2 clocks wide");

  //====================================================================
  // COVER PROPERTIES
  //--------------------------------------------------------------------
  // Each cover carries a pass action block that bumps a hit counter, and
  // the final block prints the tally.  This reports coverage identically
  // on both simulators instead of relying on a vendor-specific coverage
  // database, and makes the numbers visible in the checked-in logs.
  //====================================================================

// NOTE: the hit counters below live in a plain always block rather than
// in cover-property action blocks.  Attaching an action block to a cover
// property crashes the open-source simulator with a V3Localize internal
// error, so the bare cover properties are kept for the vendor tool's
// native coverage database and the counters mirror the same conditions
// for the portable log-based report.

  int unsigned c1_hits = 0, c2_hits = 0, c3_hits = 0, c4_hits = 0, c5_hits = 0;

  logic tx_active_q = 1'b0;
  logic rx_dv_q     = 1'b0;

  always @(posedge clk) begin
    tx_active_q <= tx_active;
    rx_dv_q     <= rx_dv;

    if ((tx_state == S_IDLE) && tx_dv && (tx_byte == 8'h00)) c1_hits <= c1_hits + 1;
    if ((tx_state == S_IDLE) && tx_dv && (tx_byte == 8'hFF)) c2_hits <= c2_hits + 1;
    if (tx_active && !tx_active_q && (idle_cnt < 32'd16))    c3_hits <= c3_hits + 1;
    if (tx_active && !tx_active_q && (idle_cnt > 32'd500))   c4_hits <= c4_hits + 1;
    if (rx_dv && !rx_dv_q)                                   c5_hits <= c5_hits + 1;
  end

  // C1 - all-zeros payload accepted (start bit adjacent to a 0 data bit)
  c_payload_all_zeros : cover property (
    @(posedge clk) (tx_state == S_IDLE) && tx_dv && (tx_byte == 8'h00));

  // C2 - all-ones payload accepted (data bits adjacent to the stop bit)
  c_payload_all_ones : cover property (
    @(posedge clk) (tx_state == S_IDLE) && tx_dv && (tx_byte == 8'hFF));

  // C3 - back-to-back burst: new frame launched almost immediately after
  //      the previous one drained (the 70% delay==0 leg of the stress mix)
  c_burst_back_to_back : cover property (
    @(posedge clk) $rose(tx_active) && (idle_cnt < 32'd16));

  // C4 - long idle hold: receiver sat idle a long time before the next
  //      frame (the 10% delay==1000 leg of the stress mix)
  c_long_idle_gap : cover property (
    @(posedge clk) $rose(tx_active) && (idle_cnt > 32'd500));

  // C5 - a complete frame made it through the loopback and out of the RX
  c_rx_frame_complete : cover property (
    @(posedge clk) $rose(rx_dv));

  //--------------------------------------------------------------------
  // Coverage report
  //--------------------------------------------------------------------
  final begin
    $display("=========== SVA COVER PROPERTY HITS ===========");
    $display("  C1 payload_all_zeros    : %0d", c1_hits);
    $display("  C2 payload_all_ones     : %0d", c2_hits);
    $display("  C3 burst_back_to_back   : %0d", c3_hits);
    $display("  C4 long_idle_gap        : %0d", c4_hits);
    $display("  C5 rx_frame_complete    : %0d", c5_hits);
    if (c1_hits && c2_hits && c3_hits && c4_hits && c5_hits)
      $display("  COVERAGE: 5/5 cover properties HIT");
    else
      $display("  COVERAGE: HOLE - not all cover properties reached");
    $display("===============================================");
  end

endmodule : uart_sva_checker

`endif // UART_SVA_CHECKER_SV
