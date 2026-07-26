//======================================================================
// uart_sva_bind.sv
//----------------------------------------------------------------------
// Attaches uart_sva_checker to every uart_top instance without touching
// the RTL.  The last three connections are hierarchical references into
// the TX_INST sub-instance -- legal because the bind is elaborated in
// uart_top's scope, and it keeps the white-box FSM taps out of the DUT
// source.
//
// CLKS_PER_BIT is forwarded from the DUT instance so the checker's
// baud-period arithmetic tracks whatever the regression overrides it to.
//======================================================================
`ifndef UART_SVA_BIND_SV
`define UART_SVA_BIND_SV

bind uart_top uart_sva_checker #(
    .CLKS_PER_BIT (CLKS_PER_BIT)
) u_uart_sva (
    .clk         (i_Clock),

    .tx_dv       (i_Tx_DV),
    .tx_byte     (i_Tx_Byte),
    .tx_active   (o_Tx_Active),
    .tx_done     (o_Tx_Done),
    .tx_serial   (w_Serial_Line),
    .rx_dv       (o_Rx_DV),
    .rx_byte     (o_Rx_Byte),

    .tx_state    (TX_INST.r_SM_Main),
    .tx_clk_cnt  (TX_INST.r_Clock_Count),
    .tx_data_lat (TX_INST.r_Tx_Data)
);

`endif // UART_SVA_BIND_SV
