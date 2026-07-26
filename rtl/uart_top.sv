module uart_top 
  #(parameter CLKS_PER_BIT = 87) // Default: 115200 baud @ 10MHz
  (
    input        i_Clock,
    // TX Inputs (Driven by UVM Driver)
    input        i_Tx_DV,
    input [7:0]  i_Tx_Byte, 
    
    // Status Outputs (Monitored by UVM)
    output       o_Tx_Active,
    output       o_Tx_Done,
    
    // RX Outputs (Monitored by UVM)
    output       o_Rx_DV,
    output [7:0] o_Rx_Byte
   );

  // The internal wire connecting TX output to RX input
  wire w_Serial_Line;

  // UART Transmitter
  uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) TX_INST (
    .i_Clock(i_Clock),
    .i_Tx_DV(i_Tx_DV),
    .i_Tx_Byte(i_Tx_Byte),
    .o_Tx_Active(o_Tx_Active),
    .o_Tx_Serial(w_Serial_Line), // <- WIRED TO RX
    .o_Tx_Done(o_Tx_Done)
  );

  // UART Receiver
  uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) RX_INST (
    .i_Clock(i_Clock),
    .i_Rx_Serial(w_Serial_Line), // <- WIRED TO TX
    .o_Rx_DV(o_Rx_DV),
    .o_Rx_Byte(o_Rx_Byte)
  );

endmodule