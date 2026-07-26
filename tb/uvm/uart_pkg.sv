package uart_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // Objects
    `include "uart_item.sv"
    `include "uart_sequence.sv" 

    // Components
    `include "uart_driver.sv"
    `include "uart_monitor.sv"
    `include "uart_agent.sv"
    `include "uart_scoreboard.sv"
    `include "uart_env.sv"
    
    // The Test
    `include "uart_test.sv"
    
endpackage