# Third-Party Notices

## Device under test

`rtl/uart_tx.v` and `rtl/uart_rx.v` are **not** original work in this
repository. Both files carry the header:

```
// File Downloaded from http://www.nandland.com
```

They are redistributed unmodified so that the verification results in
this repository can be reproduced. Neither file carries an embedded
copyright or licence notice, so no licence is asserted for them here.
The MIT licence in `LICENSE` covers only the verification environment,
the assertion checker, the build flow and the documentation.

If you intend to reuse this repository for anything beyond study or
reproduction of these results, confirm the current terms directly with
nandland.com, or substitute your own UART RTL. The testbench binds to
the port list of `uart_top.sv` and the FSM state encoding of
`uart_tx.v`, so a substitute DUT would require the bind connections in
`tb/sva/uart_sva_bind.sv` to be updated.

`rtl/uart_top.sv`, which wires the transmitter and receiver into a
loopback, is original work and is covered by `LICENSE`.

## Tooling

The UVM library is not vendored in this repository. `make uvm_vl`
expects an Accellera `uvm-core` checkout via `UVM_HOME`; UVM is licensed
by Accellera under the Apache License 2.0.
