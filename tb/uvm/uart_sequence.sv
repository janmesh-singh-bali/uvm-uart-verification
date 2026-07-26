//======================================================================
// uart_sequence.sv
//----------------------------------------------------------------------
// Stress sequence for the UART loopback DUT.
//
//   Phase 1 : 5x 0x00 back-to-back      (start bit adjacent to a 0 bit)
//   Phase 2 : 5x 0xFF with short gaps   (data bits adjacent to stop bit)
//   Phase 3 : 50x weighted random       (70% burst / 20% gap / 10% hold)
//
// All three phases go through req.randomize(), so the c_stress_timing
// distribution constraint declared in uart_item is what actually shapes
// the traffic.  The directed phases pin data with inline "randomize()
// with" rather than post-create field assignment, which keeps the
// solver in charge and stops the constraint becoming dead code.
//======================================================================

class uart_stress_sequence extends uvm_sequence #(uart_item);
    `uvm_object_utils(uart_stress_sequence)

    // Knobs, overridable from the test
    int unsigned n_zeros  = 5;
    int unsigned n_ones   = 5;
    int unsigned n_random = 50;

    function new(string name = "uart_stress_sequence");
        super.new(name);
    endfunction

    virtual task body();
        uart_item req;

        `uvm_info("SEQ", $sformatf("Stress profile: %0d zeros, %0d ones, %0d random",
                                   n_zeros, n_ones, n_random), UVM_LOW)

        // ------------------------------------------------------------
        // PHASE 1 - all-zeros payload, zero inter-frame delay (burst).
        // Exercises the start-bit / first-data-bit boundary: the line
        // stays low across the transition, so a short start bit or a
        // per-bit timing slip shows up here first.
        // ------------------------------------------------------------
        repeat (n_zeros) begin
            req = uart_item::type_id::create("req");
            start_item(req);
            if (!req.randomize() with { data == 8'h00; delay == 0; })
                `uvm_fatal("SEQ", "randomize failed on all-zeros phase")
            finish_item(req);
        end

        // ------------------------------------------------------------
        // PHASE 2 - all-ones payload with a short gap.
        // Exercises the last-data-bit / stop-bit boundary, where the
        // line stays high across the transition.
        // ------------------------------------------------------------
        repeat (n_ones) begin
            req = uart_item::type_id::create("req");
            start_item(req);
            if (!req.randomize() with { data == 8'hFF; delay inside {[1:20]}; })
                `uvm_fatal("SEQ", "randomize failed on all-ones phase")
            finish_item(req);
        end

        // ------------------------------------------------------------
        // PHASE 3 - unconstrained data, delay shaped by c_stress_timing
        // (70% delay==0, 20% delay in [1:20], 10% delay==1000).
        // ------------------------------------------------------------
        repeat (n_random) begin
            req = uart_item::type_id::create("req");
            start_item(req);
            if (!req.randomize())
                `uvm_fatal("SEQ", "randomize failed on random stress phase")
            finish_item(req);
        end

    endtask

endclass
