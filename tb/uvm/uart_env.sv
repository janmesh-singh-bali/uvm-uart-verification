class uart_env extends uvm_env;
    `uvm_component_utils(uart_env)

    uart_agent agnt;
    uart_scoreboard scb;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agnt = uart_agent::type_id::create("agnt", this);
        scb  = uart_scoreboard::type_id::create("scb", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);

        agnt.umon.item_sent_port.connect(scb.port_sent);
        agnt.umon.item_got_port.connect(scb.port_got);
        
    endfunction
endclass