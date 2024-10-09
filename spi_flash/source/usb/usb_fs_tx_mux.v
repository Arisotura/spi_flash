module usb_fs_tx_mux (
  // interface to IN Protocol Engine
  input wire in_tx_pkt_start,
  input wire [3:0] in_tx_pid,

  // interface to OUT Protocol Engine
  input wire out_tx_pkt_start,
  input wire [3:0] out_tx_pid,

  // interface to tx module
  output wire tx_pkt_start,
  output wire [3:0] tx_pid
);
  assign tx_pkt_start = in_tx_pkt_start | out_tx_pkt_start;
  assign tx_pid = out_tx_pkt_start ? out_tx_pid : in_tx_pid;
endmodule
