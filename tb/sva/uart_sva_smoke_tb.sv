//======================================================================
// uart_sva_smoke_tb.sv
//----------------------------------------------------------------------
// Lightweight, UVM-free smoke testbench whose only job is to exercise
// the bound assertion checker.  It replays the same stimulus profile as
// uart_stress_sequence (5x 0x00 burst, 5x 0xFF with gaps, 50 weighted
// random) so that every assertion and every cover property sees the
// traffic it was written for.
//
// Why this exists: it runs on a stock open-source simulator with no UVM
// library present, which makes the assertion results reproducible by
// anyone who clones the repo.  The full UVM regression is the real
// verification flow; this is the assertion sign-off harness.
//======================================================================
`timescale 1ns/1ps

module uart_sva_smoke_tb;

  parameter int CLKS_PER_BIT = 868;

  bit         clk = 0;
  logic       tx_dv;
  logic [7:0] tx_byte;
  logic       tx_active, tx_done, rx_dv;
  logic [7:0] rx_byte;

  int unsigned sent_cnt = 0;
  int unsigned recv_cnt = 0;
  int unsigned err_cnt  = 0;
  logic [7:0] expect_q [$];

  always #5 clk = ~clk;   // 100 MHz

  uart_top #(.CLKS_PER_BIT(CLKS_PER_BIT)) DUT (
      .i_Clock     (clk),
      .i_Tx_DV     (tx_dv),
      .i_Tx_Byte   (tx_byte),
      .o_Tx_Active (tx_active),
      .o_Tx_Done   (tx_done),
      .o_Rx_DV     (rx_dv),
      .o_Rx_Byte   (rx_byte)
  );

  // ---------------------------------------------------------------
  // Reference model: same queue-compare policy as the UVM scoreboard
  // ---------------------------------------------------------------
  always @(posedge clk) begin
    if (rx_dv) begin
      logic [7:0] exp;
      recv_cnt++;
      if (expect_q.size() == 0) begin
        $display("[SMOKE] ERROR: RX byte 0x%02h with empty expect queue", rx_byte);
        err_cnt++;
      end else begin
        exp = expect_q.pop_front();
        if (exp !== rx_byte) begin
          $display("[SMOKE] ERROR: expected 0x%02h got 0x%02h", exp, rx_byte);
          err_cnt++;
        end
      end
    end
  end

  // ---------------------------------------------------------------
  task automatic send_byte(input logic [7:0] data, input int gap);
    @(posedge clk);
    #1;                       // drive off the edge: avoids a sample race
    tx_byte = data;
    tx_dv   = 1'b1;
    expect_q.push_back(data);
    sent_cnt++;
    @(posedge clk);
    #1;
    tx_dv = 1'b0;
    @(posedge tx_done);
    if (gap > 0) repeat (gap) @(posedge clk);
  endtask

  // Watchdog
  initial begin
    #200ms;
    $display("[SMOKE] WATCHDOG TIMEOUT: sent=%0d recv=%0d", sent_cnt, recv_cnt);
    $finish;
  end

  // ---------------------------------------------------------------
  initial begin
    int prob;
    tx_dv   = 1'b0;
    tx_byte = 8'h00;
    repeat (10) @(posedge clk);

    // Directed corner case 1: all-zeros, back to back
    repeat (5) send_byte(8'h00, 0);

    // Directed corner case 2: all-ones, small gaps
    repeat (5) send_byte(8'hFF, $urandom_range(1, 20));

    // Weighted random stress: 70% burst / 20% short gap / 10% long hold
    repeat (50) begin
      prob = $urandom_range(0, 99);
      if (prob < 70)      send_byte($urandom_range(0, 255), 0);
      else if (prob < 90) send_byte($urandom_range(0, 255), $urandom_range(1, 20));
      else                send_byte($urandom_range(0, 255), 1000);
    end

    repeat (CLKS_PER_BIT * 12) @(posedge clk);

    $display("--------------------------------------------------");
    $display("[SMOKE] CLKS_PER_BIT = %0d", CLKS_PER_BIT);
    $display("[SMOKE] bytes sent     = %0d", sent_cnt);
    $display("[SMOKE] bytes received = %0d", recv_cnt);
    $display("[SMOKE] data mismatches= %0d", err_cnt);
    if (err_cnt == 0 && sent_cnt == recv_cnt)
      $display("[SMOKE] RESULT: PASS");
    else
      $display("[SMOKE] RESULT: FAIL");
    $display("--------------------------------------------------");
    $finish;
  end

endmodule
