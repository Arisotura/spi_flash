`include "usb_fs_in_arb.v"
`include "usb_fs_in_pe.v"
`include "usb_fs_out_arb.v"
`include "usb_fs_out_pe.v"
`include "usb_fs_tx.v"
`include "usb_fs_tx_mux.v"
`include "usb_fs_rx.v"

module usb_fs_pe #(
  parameter [4:0] NUM_OUT_EPS = 1,
  parameter [4:0] NUM_IN_EPS = 1
) (
  input wire clk_48mhz,
  input wire clk,
  input wire [6:0] dev_addr,

  ////////////////////////////////////////////////////////////////////////////////
  ////////////////////////////////////////////////////////////////////////////////
  /// USB Endpoint Interface
  ////////////////////////////////////////////////////////////////////////////////
  ////////////////////////////////////////////////////////////////////////////////

  ////////////////////
  // global endpoint interface 
  ////////////////////
  input wire reset,


  ////////////////////
  // out endpoint interfaces 
  ////////////////////
  input wire [NUM_OUT_EPS-1:0] out_ep_req,
  output wire [NUM_OUT_EPS-1:0] out_ep_grant,
  output wire [NUM_OUT_EPS-1:0] out_ep_data_avail,
  output wire [NUM_OUT_EPS-1:0] out_ep_setup,
  input wire [NUM_OUT_EPS-1:0] out_ep_data_get,
  output wire [7:0] out_ep_data,
  input wire [NUM_OUT_EPS-1:0] out_ep_stall,
  output wire [NUM_OUT_EPS-1:0] out_ep_acked,


  ////////////////////
  // in endpoint interfaces 
  ////////////////////
  input wire [NUM_IN_EPS-1:0] in_ep_req,
  output wire [NUM_IN_EPS-1:0] in_ep_grant,
  output wire [NUM_IN_EPS-1:0] in_ep_data_free,
  input wire [NUM_IN_EPS-1:0] in_ep_data_put,
  input wire [(NUM_IN_EPS*8)-1:0] in_ep_data,
  input wire [NUM_IN_EPS-1:0] in_ep_data_done,
  input wire [NUM_IN_EPS-1:0] in_ep_stall,
  output wire [NUM_IN_EPS-1:0] in_ep_acked,

  
  ////////////////////
  // sof interface
  ////////////////////
  output wire sof_valid,
  output wire [10:0] frame_index,



  ////////////////////////////////////////////////////////////////////////////////
  ////////////////////////////////////////////////////////////////////////////////
  /// USB TX/RX Interface
  ////////////////////////////////////////////////////////////////////////////////
  ////////////////////////////////////////////////////////////////////////////////
  output wire usb_p_tx,
  output wire usb_n_tx,

  input  wire usb_p_rx,
  input  wire usb_n_rx,

  output wire usb_tx_en
);
  // in pe interface
  wire [7:0] arb_in_ep_data;

  // rx interface
  wire bit_strobe;
  wire rx_pkt_start;
  wire rx_pkt_end;
  wire [3:0] rx_pid;
  wire [6:0] rx_addr;
  wire [3:0] rx_endp;
  wire [10:0] rx_frame_num;
  wire rx_data_put;
  wire [7:0] rx_data;
  wire rx_pkt_valid;

  // tx mux
  wire in_tx_pkt_start;
  wire [3:0] in_tx_pid;
  wire out_tx_pkt_start;
  wire [3:0] out_tx_pid;
  
  // tx interface
  wire tx_pkt_start;
  wire tx_pkt_end;
  wire [3:0] tx_pid;
  wire tx_data_avail;
  wire tx_data_get;
  wire [7:0] tx_data;

  // sof interface
  assign sof_valid = rx_pkt_end && rx_pkt_valid && rx_pid == 4'b0101;
  assign frame_index = rx_frame_num;


  usb_fs_in_arb #(
    .NUM_IN_EPS(NUM_IN_EPS)
  ) usb_fs_in_arb_inst (
    // endpoint interface 
    .in_ep_req(in_ep_req),
    .in_ep_grant(in_ep_grant),
    .in_ep_data(in_ep_data),

    // protocol engine interface 
    .arb_in_ep_data(arb_in_ep_data)
  );

  usb_fs_out_arb #(
    .NUM_OUT_EPS(NUM_OUT_EPS)
  ) usb_fs_out_arb_inst (
    // endpoint interface 
    .out_ep_req(out_ep_req),
    .out_ep_grant(out_ep_grant)
  );

  usb_fs_in_pe #(
    .NUM_IN_EPS(NUM_IN_EPS)
  ) usb_fs_in_pe_inst (
    .clk(clk),
    .reset(reset),
    .reset_ep({NUM_IN_EPS{1'b0}}),
    .dev_addr(dev_addr),

    // endpoint interface 
    .in_ep_data_free(in_ep_data_free),
    .in_ep_data_put(in_ep_data_put),
    .in_ep_data(arb_in_ep_data),
    .in_ep_data_done(in_ep_data_done),
    .in_ep_stall(in_ep_stall),
    .in_ep_acked(in_ep_acked),

    // rx path 
    .rx_pkt_start(rx_pkt_start),
    .rx_pkt_end(rx_pkt_end),
    .rx_pkt_valid(rx_pkt_valid),
    .rx_pid(rx_pid),
    .rx_addr(rx_addr),
    .rx_endp(rx_endp),
    .rx_frame_num(rx_frame_num),

    // tx path 
    .tx_pkt_start(in_tx_pkt_start),
    .tx_pkt_end(tx_pkt_end),
    .tx_pid(in_tx_pid),
    .tx_data_avail(tx_data_avail),
    .tx_data_get(tx_data_get),
    .tx_data(tx_data)
  );

  usb_fs_out_pe #(
    .NUM_OUT_EPS(NUM_OUT_EPS)
  ) usb_fs_out_pe_inst (
    .clk(clk),
    .reset(reset),
    .reset_ep({NUM_OUT_EPS{1'b0}}),
    .dev_addr(dev_addr),

    // endpoint interface 
    .out_ep_data_avail(out_ep_data_avail),
    .out_ep_data_get(out_ep_data_get),
    .out_ep_data(out_ep_data),
    .out_ep_setup(out_ep_setup),
    .out_ep_stall(out_ep_stall),
    .out_ep_acked(out_ep_acked),

    // rx path 
    .rx_pkt_start(rx_pkt_start),
    .rx_pkt_end(rx_pkt_end),
    .rx_pkt_valid(rx_pkt_valid),
    .rx_pid(rx_pid),
    .rx_addr(rx_addr),
    .rx_endp(rx_endp),
    .rx_frame_num(rx_frame_num),
    .rx_data_put(rx_data_put),
    .rx_data(rx_data),

    // tx path 
    .tx_pkt_start(out_tx_pkt_start),
    .tx_pkt_end(tx_pkt_end),
    .tx_pid(out_tx_pid)
  );

  usb_fs_rx usb_fs_rx_inst (
    .clk_48mhz(clk_48mhz),
    .clk(clk),
    .reset(reset),
    .dp(usb_p_rx),
    .dn(usb_n_rx),
    .bit_strobe(bit_strobe),
    .pkt_start(rx_pkt_start),
    .pkt_end(rx_pkt_end),
    .pid(rx_pid),
    .addr(rx_addr),
    .endp(rx_endp),
    .frame_num(rx_frame_num),
    .rx_data_put(rx_data_put),
    .rx_data(rx_data),
    .valid_packet(rx_pkt_valid)
  );

  usb_fs_tx_mux usb_fs_tx_mux_inst (
    // interface to IN Protocol Engine
    .in_tx_pkt_start(in_tx_pkt_start),
    .in_tx_pid(in_tx_pid),

    // interface to OUT Protocol Engine
    .out_tx_pkt_start(out_tx_pkt_start),
    .out_tx_pid(out_tx_pid),

    // interface to tx module
    .tx_pkt_start(tx_pkt_start),
    .tx_pid(tx_pid)
  );

  usb_fs_tx usb_fs_tx_inst (
    .clk_48mhz(clk_48mhz),
    .clk(clk),
    .reset(reset),
    .bit_strobe(bit_strobe),
    .oe(usb_tx_en),
    .dp(usb_p_tx),
    .dn(usb_n_tx),
    .pkt_start(tx_pkt_start),
    .pkt_end(tx_pkt_end),
    .pid(tx_pid),
    .tx_data_avail(tx_data_avail),
    .tx_data_get(tx_data_get),
    .tx_data(tx_data)
  );
endmodule
