# SystemVerilog/UVM Verification of a Parameterized UART RTL

A UVM verification environment for a parameterized 8-bit UART, with an
assertion-based checker bound to the DUT and a regression that sweeps
four baud rates from a single parameterized testbench.

Runs on **Questa/ModelSim** (full UVM regression) and on **Verilator**
(assertion + loopback regression, no licence required).

---

## DUT

`rtl/uart_top.sv` instantiates a transmitter and a receiver and wires
`o_Tx_Serial` straight into `i_Rx_Serial` through an internal wire:

```
  i_Tx_DV   ->  uart_tx  --w_Serial_Line-->  uart_rx  ->  o_Rx_DV
  i_Tx_Byte                                              o_Rx_Byte
```

So there is no serial pin at the DUT boundary; the testbench drives a
parallel byte in and checks the parallel byte that falls out the other
side, one full UART frame later. `CLKS_PER_BIT` sets the baud divisor
and is overridden at elaboration time by the regression.

`uart_tx.v` and `uart_rx.v` are third-party RTL from nandland.com. The
verification environment, the assertion checker and the build flow are
the original work here.

---

## Layout

```
rtl/                       DUT
  uart_tx.v                  transmitter FSM
  uart_rx.v                  receiver FSM (2-stage input synchroniser)
  uart_top.sv                loopback wrapper

tb/top/
  uart_if.sv                 signal-level interface
  tb_top.sv                  clock gen, DUT instance, config_db, run_test

tb/uvm/
  uart_item.sv               transaction: data + inter-frame delay
  uart_sequence.sv           directed corner cases + weighted random stress
  uart_driver.sv             drives i_Tx_DV / i_Tx_Byte, waits on o_Tx_Done
  uart_monitor.sv            forked TX and RX sampling threads
  uart_scoreboard.sv         queue-based compare, dual analysis imports
  uart_agent.sv              active/passive
  uart_env.sv                agent + scoreboard, TLM connections
  uart_test.sv               objection handling, sequence start
  uart_pkg.sv                compile order

tb/sva/
  uart_sva_checker.sv        7 assertions + 5 cover properties
  uart_sva_bind.sv           binds the checker into uart_top
  uart_sva_smoke_tb.sv       UVM-free harness for assertion sign-off

sim/
  Makefile                   both flows
  vl_115200.log              Verilator assertion regression log
  log_*.log                  Questa UVM regression logs
```

---

## Verification environment

**Stimulus.** Three phases, all through `randomize()` so the
`c_stress_timing` distribution constraint in `uart_item` is what shapes
the traffic:

| Phase | Payload | Inter-frame delay | Purpose |
|-------|---------|-------------------|---------|
| 1 | `8'h00` x5 | 0 (burst) | start bit adjacent to a 0 data bit |
| 2 | `8'hFF` x5 | `[1:20]` | last data bit adjacent to the stop bit |
| 3 | random x50 | `dist { 0:=70, [1:20]:=20, 1000:=10 }` | burst / gap / long-hold mix |

60 transactions per run.

**Checking.** Two independent mechanisms:

1. *Scoreboard* — the monitor's TX thread pushes every accepted byte onto
   a queue; the RX thread pops and compares. Two `write` methods on one
   scoreboard, so `uvm_analysis_imp_decl(_sent)` and `(_got)` are used to
   get two distinct analysis imports.
2. *Assertions* — `uart_sva_checker` is bound into `uart_top` and watches
   the framing directly, including the internal `w_Serial_Line` and
   white-box taps into the TX FSM. The scoreboard proves data integrity;
   the assertions prove the bit-level timing that produced it.

### Assertions

| # | Name | What it proves |
|---|------|----------------|
| A1 | `a_start_bit_low` | serial line is driven low once `tx_active` rises |
| A2 | `a_start_bit_duration` | FSM cannot leave the start bit before `CLKS_PER_BIT` clocks |
| A3 | `a_tx_bit_stable` | line holds for the whole bit period — per-bit stability against `CLKS_PER_BIT` |
| A4 | `a_stop_bit_high` | stop bit is held high for its full period |
| A5 | `a_line_idle_high` | line idles in mark state between frames |
| A6 | `a_no_frame_overlap` | a second `i_Tx_DV` mid-frame cannot overwrite the latched payload |
| A7 | `a_tx_done_pulse` | `o_Tx_Done` is exactly two clocks wide |

A7 is worth a note. The nandland header comment says `o_Tx_Done` is
driven high for one clock cycle. It is not: `r_Tx_Done` is set both on
the final `s_TX_STOP_BIT` clock and again in `s_CLEANUP`, and is only
cleared back in `s_IDLE`, so the real pulse is two clocks. The assertion
pins the actual behaviour rather than the documented one.

### Cover properties

| # | Name | Reaches |
|---|------|---------|
| C1 | `c_payload_all_zeros` | all-zeros payload accepted |
| C2 | `c_payload_all_ones` | all-ones payload accepted |
| C3 | `c_burst_back_to_back` | new frame launched immediately after the previous drained |
| C4 | `c_long_idle_gap` | long idle hold before the next frame |
| C5 | `c_rx_frame_complete` | a frame survived the loopback and came out of the RX |

C3 and C4 exist to prove the weighted delay distribution actually
reached both extremes rather than clustering in the middle.

---

## Running it

### Verilator (no licence needed)

```bash
cd sim
make sva            # build the assertion harness at 115200
make sva_regress    # rebuild + run at 9600 / 19200 / 57600 / 115200
```

`CLKS_PER_BIT` is an elaboration-time parameter, so each baud rate is a
separate build; `sva_regress` loops over all four and greps the results.

### Questa / ModelSim

```bash
cd sim
make q_compile
make q_regression   # UVM regression across all four baud rates
```

### Full UVM on Verilator

```bash
export UVM_HOME=/path/to/uvm-core
cd sim && make uvm_vl
```

Requires Verilator **>= 5.050**. Earlier 5.0xx releases hit a scheduler
convergence problem on virtual-interface writes issued from class tasks,
which is precisely what a UVM driver does.

---

## Results

Verilator assertion regression, `CLKS_PER_BIT=868` (115200 baud on a
100 MHz clock) — see `sim/vl_115200.log`:

```
[SMOKE] bytes sent     = 60
[SMOKE] bytes received = 60
[SMOKE] data mismatches= 0
[SMOKE] RESULT: PASS

  C1 payload_all_zeros    : 5
  C2 payload_all_ones     : 5
  C3 burst_back_to_back   : 50
  C4 long_idle_gap        : 6
  C5 rx_frame_complete    : 60
  COVERAGE: 5/5 cover properties HIT
```

No assertion failures. Questa UVM regression logs (`sim/log_*.log`) show
0 `UVM_ERROR` / 0 `UVM_FATAL` across all four baud rates, 60 driven bytes
and 120 scoreboard reports per run.

---

## Notes on SVA portability

The checker is deliberately restricted to a conservative SVA subset so
one source file elaborates on both simulators. Three constraints drove
that, all found by trying the obvious thing first and watching it fail:

- **No `##N` cycle delays.** Verilator rejects `## (in sequence
  expression)` outright. A2 was originally
  `$rose(tx_active) |-> ##CLKS_PER_BIT (tx_serial == 0)` and had to be
  re-expressed as an FSM-state guard; A7 was two chained `##1` terms and
  is now written with `$past(tx_done, 1..3)`.
- **No action blocks on cover properties.** Attaching `c1_hits++` to a
  `cover property` crashes Verilator with a `V3Localize` internal error.
  The cover properties are therefore bare — the vendor tool collects them
  natively — and the hit counters are mirrored in a plain `always` block
  so the counts also appear in the log on either simulator.
- **Also avoided:** `[*N]` repetition, unbounded ranges, local variables
  in sequences, `throughout` / `within` / `intersect`.

What remains is `|->`, `|=>`, `$rose`, `$fell`, `$stable` and `$past`,
which both tools handle.

One more portability trap, in the stimulus rather than the assertions:
Verilator demotes non-blocking assignments reached from an `initial`
block to blocking assignments. Driving the DUT exactly on the clock edge
therefore races the RTL's own sampling and the simulation hangs on the
first `@(posedge tx_done)`. `uart_sva_smoke_tb.sv` drives at `#1` past
the edge to avoid it.
