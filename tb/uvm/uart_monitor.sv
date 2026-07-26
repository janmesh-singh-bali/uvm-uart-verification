class uart_monitor extends uvm_monitor;
    `uvm_component_utils(uart_monitor)

    function new(input string name = "uart_monitor", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // Get analysis port from the interface-dut    
    uvm_analysis_port #(uart_item) item_sent_port;
    uvm_analysis_port #(uart_item) item_got_port;

    virtual uart_if uif;

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        item_sent_port = new("item_sent_port", this);
        item_got_port = new("item_got_port", this);

        // Get the interface handler
        if(!uvm_config_db #(virtual uart_if)::get(this, "", "uif", uif))
            `uvm_fatal("NO_VIF", {"Virtual interface not set for: ", get_full_name(), ". Check tb_top!"})
    endfunction

    task monitor_tx();
        uart_item item; 

        forever begin
            // Wait for the driver to assert valid bit
            @(posedge uif.clk);
            if(uif.tx_dv) begin
                // Write the tx data to the factory
                item = uart_item::type_id::create("item_sent");
                item.data = uif.tx_byte; 

                // Sent tx to scoreboard fifo and write in the terminal for log
                `uvm_info("MON", $sformatf("Sampled TX: %0h", item.data) ,UVM_LOW)
                item_sent_port.write(item);

                // Wait until the transaction has done
                @(posedge uif.tx_done);
            end
        end
    endtask

    task monitor_rx();
        uart_item item;
        forever begin
            // Wait for the receiver to assert valid
            @(posedge uif.clk);
            if(uif.rx_dv) begin
                item = uart_item::type_id::create("item_got");
                item.data = uif.rx_byte;

                // sent this to scoreboard to store in fifo
                `uvm_info("MON", $sformatf("Sampled RX: 0x%0h", item.data), UVM_LOW)
                item_got_port.write(item);
            end
        end
    endtask

    virtual task run_phase(uvm_phase phase);
            fork
                monitor_tx();   // Thread 1 watches tx
                monitor_rx();   // Thread 2 watches rx
            join_none
    endtask

endclass