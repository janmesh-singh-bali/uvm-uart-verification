// We have two write inputs here one for rx and one for tx
// however regular uvm_analysis_imp can only work for one
// therfore we declate these outside of the class to support
// two seperate write lines 
`uvm_analysis_imp_decl(_sent)
`uvm_analysis_imp_decl(_got)

// This is erquired since single scoreboard/monitor design 
// has planned 

class uart_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(uart_scoreboard)

    function new(input string name = "uart_scoreboard", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    uvm_analysis_imp_sent #(uart_item, uart_scoreboard) port_sent;
    uvm_analysis_imp_got #(uart_item, uart_scoreboard) port_got;

    // FIFO
    uart_item queue[$];

    // Why this is not virtual?
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        // Initialize ports
        port_sent = new("port_sent", this);
        port_got = new("port_got", this);
    endfunction

    // The macro looks for "write_sent"
    virtual function void write_sent(uart_item tr);
        // Logic: Push to Queue
        `uvm_info("SCB", $sformatf("Queue Push: 0x%0h", tr.data), UVM_LOW)
        queue.push_back(tr);
    endfunction

    // The macro looks for "write_got"
    virtual function void write_got(uart_item tr);
        uart_item expected;
        
        // Check Queue
        if (queue.size() == 0) begin
            `uvm_error("SCB", "FAIL: Received data when queue was empty!")
            return;
        end

        // Pop the oldest item
        expected = queue.pop_front();

        // Compare
        if (expected.data !== tr.data) begin
            `uvm_error("SCB", $sformatf("FAIL: Expected 0x%0h, Got 0x%0h", expected.data, tr.data))
        end else begin
            `uvm_info("SCB", $sformatf("PASS! Matched 0x%0h", tr.data), UVM_LOW)
        end
    endfunction

endclass