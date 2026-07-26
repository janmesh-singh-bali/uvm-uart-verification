module tb_top;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    
    import uart_pkg::*;

    // ----------------------------------------------------------------
    // 1. PARAMETERIZED CONFIGURATION
    // ----------------------------------------------------------------
    // Default: 115200 Baud @ 100MHz Clock (100M / 115200 = ~868)
    parameter int CLKS_PER_BIT = 868; 

    // Clock Generation (100MHz)
    bit clk;
    initial clk = 0;
    always #5 clk = ~clk; 

    // Interface
    uart_if uif(clk);

    // ----------------------------------------------------------------
    // 2. DUT INSTANCE (With Parameter Override)
    // ----------------------------------------------------------------
    uart_top #(
        .CLKS_PER_BIT(CLKS_PER_BIT) // The Makefile controls this to test various baud rates
    ) DUT (
        .i_Clock    (clk),
        .i_Tx_DV    (uif.tx_dv),
        .i_Tx_Byte  (uif.tx_byte),
        .o_Tx_Active(uif.tx_active),
        .o_Tx_Done  (uif.tx_done),
        .o_Rx_DV    (uif.rx_dv),
        .o_Rx_Byte  (uif.rx_byte)
    );

    // ----------------------------------------------------------------
    // 3. UVM STARTUP
    // ----------------------------------------------------------------
    initial begin
        // Store the Baud Rate in DB
        uvm_config_db #(int)::set(null, "*", "CLKS_PER_BIT", CLKS_PER_BIT);
        
        // Store Interface
        uvm_config_db #(virtual uart_if)::set(null, "*", "uif", uif);

        // Print the current speed to log
        $display("------------------------------------------------");
        $display("TB_TOP: Running with CLKS_PER_BIT = %0d", CLKS_PER_BIT);
        $display("------------------------------------------------");

        run_test("uart_test");
    end

endmodule