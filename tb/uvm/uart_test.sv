class uart_test extends uvm_test;
    `uvm_component_utils(uart_test)

    uart_env env;
    uart_stress_sequence seq;

    function new(input string name = "uart_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = uart_env::type_id::create("env", this);
        
        // Create the sequence here
        seq = uart_stress_sequence::type_id::create("seq", this);
    endfunction

    virtual task run_phase(uvm_phase phase);
        
        // raise objection
        phase.raise_objection(this);

        `uvm_info("TEST", "Starting Sequence...", UVM_LOW)
        
        seq.start(env.agnt.seqr);
        
        `uvm_info("TEST", "Sequence Finished.", UVM_LOW)
        
        // time for the scoreboard to settle
        #2000;

        // drop objection
        phase.drop_objection(this);    
            
    endtask

endclass