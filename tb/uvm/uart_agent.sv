class uart_agent extends uvm_agent;
    `uvm_component_utils(uart_agent)

    function new(input string name = "uart_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // Components
    uart_driver udrv;
    uart_monitor umon;

    // standard  uvm sequencer
    uvm_sequencer #(uart_item) seqr;

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        // Monitor is always driven -> factory component
        umon = uart_monitor::type_id::create("umon", this);

        // Driver & Sequencer are created only if agent is active
        if(get_is_active() == UVM_ACTIVE) begin
            udrv = uart_driver::type_id::create("udrv", this);
            seqr = uvm_sequencer #(uart_item)::type_id::create("seqr", this);
        end
    endfunction 

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if(get_is_active() == UVM_ACTIVE) begin
            udrv.seq_item_port.connect(seqr.seq_item_export);
        end    
    endfunction

endclass