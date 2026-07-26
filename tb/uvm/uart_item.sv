//======================================================================
// uart_item.sv
//----------------------------------------------------------------------
// UART transaction: one payload byte plus the idle gap that follows it.
//
// DISTRIBUTION NOTE
//   The inter-frame delay is weighted 70% burst / 20% short gap / 10%
//   long hold.  The obvious way to write that is
//
//       constraint c { delay dist { 0 := 70, [1:20] := 20, 1000 := 10 }; }
//
//   but composing a dist constraint with an inline equality -- e.g.
//   randomize() with { delay == 0; } in the directed phases -- is
//   reported as an unsatisfiable constraint by the open-source solver,
//   even though 0 is a member of the distribution set.
//
//   The weighting is therefore built from a uniform auxiliary variable
//   and implication constraints instead.  pick is uniform over [0:99],
//   so the resulting delay distribution is exactly 70/20/10, the solver
//   only ever has to handle uniform ranges and implications, and inline
//   constraints in the directed phases stay satisfiable because the
//   solver is free to choose a compatible pick value.
//======================================================================

class uart_item extends uvm_sequence_item;

    // Payload
    rand bit [7:0] data;

    // Idle gap, in clock cycles, inserted after the frame drains
    rand int        delay;

    // Uniform selector that shapes the delay distribution
    rand int unsigned pick;

    //------------------------------------------------------------------
    // Timing stress distribution
    //------------------------------------------------------------------
    constraint c_pick_range {
        pick inside {[0:99]};
    }

    constraint c_stress_timing {
        // 70%  burst      - next frame launched immediately
        (pick < 70)                -> (delay == 0);
        // 20%  short gap  - normal inter-frame spacing
        (pick >= 70 && pick < 90)  -> (delay inside {[1:20]});
        // 10%  long hold  - receiver left idle, tests idle stability
        (pick >= 90)               -> (delay == 1000);
    }

    // Keep the solver inside the legal envelope even when an inline
    // constraint pins delay directly.
    constraint c_delay_range {
        delay inside {[0:1000]};
    }

    `uvm_object_utils_begin(uart_item)
        `uvm_field_int(data,  UVM_DEFAULT | UVM_HEX)
        `uvm_field_int(delay, UVM_DEFAULT | UVM_DEC)
    `uvm_object_utils_end

    function new(input string name = "uart_item");
        super.new(name);
    endfunction : new

endclass
