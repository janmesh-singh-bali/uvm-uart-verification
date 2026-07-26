class uart_driver extends uvm_driver #(uart_item);
    `uvm_component_utils(uart_driver)

    function new(input string name = "uart_driver", input uvm_component parent);
        super.new(name, parent);
    endfunction : new

    // Virtual interface
    virtual uart_if uif;

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        // Get the virtual interface from the config DB
        if(!uvm_config_db #(virtual uart_if)::get(this, "", "uif", uif))
            `uvm_fatal("NO_VIF", {"Virtual interface not set for: ", get_full_name(), ". Check tb_top!"})
    endfunction

    virtual task run_phase(uvm_phase phase);
        uif.tx_dv  <= 0;
        uif.tx_byte <= '0;
        
        // Wait for some time before starting
        repeat (10) @(posedge uif.clk);

        forever begin
            seq_item_port.get_next_item(req);

            // Wait to setup at clock edge
            @(posedge uif.clk);

            // Drive the UART signals
            uif.tx_byte <= req.data;
            uif.tx_dv   <= 1;
            `uvm_info("UART_DRV", $sformatf("Transmitting byte: 0x%0h", req.data), UVM_LOW)
            
            // De-assert tx_dv after one clock cycle
            @(posedge uif.clk);
            uif.tx_dv   <= 0;

            // Wait for transmission to complete
            @(posedge uif.tx_done);
            
            // IMPLEMENT THE STRESS DELAY -> from constraints
            // If delay is 0, we loop immediately (Burst).
            // If delay is 1000, we sit idle (Hold).
            if (req.delay > 0) begin
                repeat(req.delay) @(posedge uif.clk);
            end

            seq_item_port.item_done();
        end
    endtask
endclass