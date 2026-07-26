interface uart_if(input logic clk);
  
  // No reset in this RTL, but good practice to have a placeholder
  // or use it to initialize logic if needed.
  logic reset; 

  // 1. TX Signals (Input to DUT)
  logic       tx_dv;
  logic [7:0] tx_byte;
  
  // 2. TX Status (Output from DUT)
  logic       tx_active;
  logic       tx_done;
  
  // 3. RX Signals (Output from DUT)
  logic       rx_dv;
  logic [7:0] rx_byte;

endinterface