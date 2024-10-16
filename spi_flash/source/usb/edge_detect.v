`ifndef edge_detect_v
`define edge_detect_v

module rising_edge_detector ( 
  input wire clk,
  input wire in,
  output wire out
);
  reg in_q;

  always @(posedge clk) begin
    in_q <= in;
  end

  assign out = !in_q && in;
endmodule

module falling_edge_detector ( 
  input wire clk,
  input wire in,
  output wire out
);
  reg in_q;

  always @(posedge clk) begin
    in_q <= in;
  end

  assign out = in_q && !in;
endmodule

`endif
