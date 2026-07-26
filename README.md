# SystemVerilog/UVM Verification of a Parameterized UART RTL

A UVM verification environment for a parameterized 8-bit UART, with an
assertion checker bound to the DUT and a regression that sweeps four
baud rates from a single parameterized testbench.

The full environment runs on **both Verilator and Questa**, with matching
transaction counts on each.

| | Verilator 5.050 | Questa |
|---|---|---|
| UVM regression, 4 baud rates | 0 errors, 0 fatals | 0 errors, 0 fatals |
| Transactions per run | 60 driven / 120 scoreboard | 60 driven / 120 scoreboard |
| Assertions (7) | no failures | no failures |
| Cover properties (5) | 5/5 hit | 5/5 hit |

---

## DUT

`rtl/uart_top.sv` instantiates a transmitter and a receiver and wires
`o_Tx_Serial` straight into `i_Rx_Serial` through an internal wire:

```
  i_Tx_DV   ->  uart_tx  --w_Serial_Line-->  uart_rx  ->  o_Rx_DV
  i_Tx_Byte                                              o_Rx_Byte
```

There is no serial pin at the DUT boundary. The testbench drives a
parallel byte in and checks the parallel byte that falls out the other
side one full UART frame later. `CLKS_PER_BIT` sets the baud divisor and
is overridden at elaboration time by the regression.

`uart_tx.v` and `uart_rx.v` are third-party RTL — see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). The verification
environment, the assertion checker, the loopback wrapper and the build
flow are original work.

---

## Layout

```
rtl/
  uart_tx.v                  transmitter FSM        (third-party)
  uart_rx.v                  receiver FSM           (third-party)
  uart_top.sv                loopback wrapper

tb/top/
  uart_if.sv                 signal-level interface
  tb_top.sv                  clock gen, DUT instance, config_db, run_test

tb/uvm/
  uart_item.sv               transaction: payload + inter-frame delay
  uart_sequence.sv           directed corner cases + weighted random stress
  uart_driver.sv             drives i_Tx_DV / i_Tx_Byte, waits on o_Tx_Done
  uart_monitor.sv            forked TX and RX sampling threads
  uart_scoreboard.sv         queue compare, dual analysis imports
  uart_agent.sv              active / passive
  uart_env.sv                agent + scoreboard, TLM connections
  uart_test.sv               objections, sequence start
  uart_pkg.sv                compile order

tb/sva/
  uart_sva_checker.sv        7 assertions + 5 cover properties
  uart_sva_bind.sv           binds the checker into uart_top
  uart_sva_smoke_tb.sv       UVM-free harness for assertion sign-off

sim/
  Makefile                   both flows
  uvm_*.log                  Verilator UVM regression, 4 baud rates
  vl_*.log                   Verilator assertion regression, 4 baud rates
  log_*.log                  Questa UVM regression, 4 baud rates
```

---

## Verification environment

### Stimulus

Three phases, 60 transactions per run, all through `randomize()`:

| Phase | Payload | Inter-frame delay | Purpose |
|-------|---------|-------------------|---------|
| 1 | `8'h00` ×5 | 0 (burst) | start bit adjacent to a 0 data bit |
| 2 | `8'hFF` ×5 | `[1:20]` | last data bit adjacent to the stop bit |
| 3 | random ×50 | 70/20/10 weighted | burst / short gap / long hold |

The 70/20/10 weighting is built from a uniform selector plus implication
constraints rather than a `dist` constraint. See
[Portability notes](#portability-notes).

### Checking

Two independent mechanisms:

**Scoreboard.** The monitor's TX thread pushes every accepted byte onto a
queue; the RX thread pops and compares. Two `write` methods on one
scoreboard, so `uvm_analysis_imp_decl(_sent)` and `(_got)` provide two
distinct analysis imports.

**Assertions.** `uart_sva_checker` is bound into `uart_top` and watches
framing directly, including the internal `w_Serial_Line` and white-box
taps into the TX FSM. The scoreboard proves data integrity; the
assertions prove the bit-level timing that produced it.

| # | Assertion | Proves |
|---|-----------|--------|
| A1 | `a_start_bit_low` | line is driven low once `tx_active` rises |
| A2 | `a_start_bit_duration` | FSM cannot leave the start bit before `CLKS_PER_BIT` clocks |
| A3 | `a_tx_bit_stable` | line holds for the whole bit period — per-bit stability against `CLKS_PER_BIT` |
| A4 | `a_stop_bit_high` | stop bit held high for its full period |
| A5 | `a_line_idle_high` | line idles in mark state between frames |
| A6 | `a_no_frame_overlap` | a second `i_Tx_DV` mid-frame cannot overwrite the latched payload |
| A7 | `a_tx_done_pulse` | `o_Tx_Done` is exactly two clocks wide |

A7 is worth a note. The vendor header comment states that `o_Tx_Done` is
driven high for one clock cycle. It is not: `r_Tx_Done` is set both on
the final `s_TX_STOP_BIT` clock and again in `s_CLEANUP`, and is cleared
only back in `s_IDLE`, so the real pulse is two clocks wide. The
assertion pins the actual behaviour rather than the documented one.

| # | Cover property | Reaches |
|---|----------------|---------|
| C1 | `c_payload_all_zeros` | all-zeros payload accepted |
| C2 | `c_payload_all_ones` | all-ones payload accepted |
| C3 | `c_burst_back_to_back` | frame launched immediately after the previous drained |
| C4 | `c_long_idle_gap` | long idle hold before the next frame |
| C5 | `c_rx_frame_complete` | frame survived the loopback and left the RX |

C3 and C4 exist to prove the weighted delay distribution actually reached
both extremes rather than clustering in the middle.

---

## Running it

### Verilator — assertion regression

No UVM library required.

```bash
cd sim
make sva            # build at 115200
make sva_regress    # 9600 / 19200 / 57600 / 115200
```

### Verilator — full UVM regression

Requires Verilator **≥ 5.050** and an Accellera `uvm-core` checkout.

```bash
cd sim
make uvm_vl UVM_HOME=~/uvm-core BAUD=868
```

`BAUD` is the clock divisor, not the baud rate: 10417 / 5208 / 1736 / 868
correspond to 9600 / 19200 / 57600 / 115200 on a 100 MHz clock. To sweep
all four:

```bash
for b in 10417 5208 1736 868; do
  make uvm_vl UVM_HOME=~/uvm-core BAUD=$b > /tmp/uvm_$b.log 2>&1
  echo "=== $b ==="; grep -E "UVM_ERROR :|UVM_FATAL :" /tmp/uvm_$b.log
done
```

First build takes a while — Verilator translates the whole UVM library to
C++ and compiles it. Subsequent builds are much faster with `ccache`.

### Questa / ModelSim

```bash
cd sim
make q_compile
make q_regression
```

---

## Results

**Verilator, full UVM environment, `BAUD=868`** (115200 baud, 100 MHz):

```
UVM_INFO  : 307      [UART_DRV]  60
UVM_ERROR :   0      [MON]      120
UVM_FATAL :   0      [SCB]      120

  C1 payload_all_zeros    : 5
  C2 payload_all_ones     : 5
  C3 burst_back_to_back   : 42
  C4 long_idle_gap        : 6
  C5 rx_frame_complete    : 60
  COVERAGE: 5/5 cover properties HIT
```

0 errors and 0 fatals at all four divisors — see `sim/uvm_*.log`.

**Verilator, assertion harness**, all four divisors: `RESULT: PASS`, 5/5
cover properties hit, no assertion failures — see `sim/vl_*.log`.

**Questa, full UVM environment**, all four divisors: 0 `UVM_ERROR`, 0
`UVM_FATAL`, 60 driven bytes and 120 scoreboard reports per run — see
`sim/log_*.log`.

Driver, monitor and scoreboard counts are identical on both simulators,
which is the cross-check that matters: the same source produces the same
transaction-level behaviour under two independent tools.

---

## Portability notes

Getting one source tree to run on both simulators turned up four
limitations in the open-source flow. None of them changed what the
assertions check; each was worked around rather than weakened.

**`##N` cycle delays are unsupported in sequence expressions.** Verilator
rejects them outright. `a_start_bit_duration` was originally
`$rose(tx_active) |-> ##CLKS_PER_BIT (tx_serial == 0)` and is now
expressed as an FSM-state guard; `a_tx_done_pulse` used two chained `##1`
terms and is now written with `$past(tx_done, 1..3)`. What remains is
`|->`, `|=>`, `$rose`, `$fell`, `$stable` and `$past`, which both tools
handle. Also avoided: `[*N]` repetition, unbounded ranges, sequence local
variables, `throughout` / `within` / `intersect`.

**Action blocks on cover properties crash the compiler.** Attaching
`c1_hits++` to a `cover property` produced a `V3Localize` internal error.
The cover properties are therefore bare — the vendor tool collects them
natively — and hit counters mirror the same conditions in a plain
`always` block, so counts appear in the log on either simulator.

**UVM's DPI layer has no open-source backend.** `uvm_hdl.c` selects a
vendor backend by preprocessor define and fires
`#error "hdl vendor backend is missing"` when none matches, which stops
the build before any of the testbench is compiled. The flow therefore
builds with `+define+UVM_NO_DPI` and uses UVM's SystemVerilog fallbacks.
The two resulting `UVM_WARNING`s (`NO_DPI_USED`, `NO_VISIT_CHECK`) are
expected and benign.

**`dist` cannot be composed with an inline equality.** Writing the
weighting as `delay dist { 0 := 70, [1:20] := 20, 1000 := 10 }` in the
item and then constraining `randomize() with { delay == 0; }` in the
directed phase is reported as an unsatisfiable constraint, even though 0
is a member of the distribution set. `uart_item` therefore derives the
weighting from a uniform selector `pick inside {[0:99]}` plus implication
constraints. The distribution is identical, the solver only handles
uniform ranges and implications, and inline constraints in the directed
phases stay satisfiable because the solver is free to choose a compatible
`pick`.

One further trap, in the stimulus rather than the assertions: Verilator
demotes non-blocking assignments reached from an `initial` block to
blocking assignments. Driving the DUT exactly on the clock edge therefore
races the RTL's own sampling and the simulation hangs on the first
`@(posedge tx_done)`. `uart_sva_smoke_tb.sv` drives at `#1` past the edge
to avoid it.

---

## Licence

MIT for the verification environment and build flow; the DUT RTL is
third-party. See [LICENSE](LICENSE) and
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
