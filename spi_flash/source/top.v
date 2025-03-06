/*
 * ECP5 flash emulator using the ULX3S board
 *
 * Wiring is on the left headers.
 * Desolder the RV3 resistor so that the flash chip voltage is auto-selecting.
 * The LEDs are powered from this same bank, so they will not illuminate.
 */
`default_nettype none

module top(
	input wire clk_25mhz,
	output wire [7:0] led,
	output wire wifi_gpio0,
	input wire ftdi_txd, // from the ftdi chip
	output wire ftdi_rxd, // to the ftdi chip
	output wire user_programn, // reboot from the user space on the flash

	// sdram physical interface
	output wire [12:0] sdram_a,
	inout wire [15:0] sdram_d,
	output wire [1:0] sdram_ba,
	output wire sdram_clk,
	output wire sdram_cke,
	output wire sdram_wen,
	output wire sdram_csn,
	output wire [1:0] sdram_dqm,
	output wire sdram_rasn,
	output wire sdram_casn,

	// USB port directly wired to serial port
	inout wire usb_fpga_bd_dn,
	inout wire usb_fpga_bd_dp,
	output wire usb_fpga_pu_dp,
	output wire usb_fpga_pu_dn,

	// GPIO pins, to be assigned
	inout wire [27:0] gp,
	output wire [27:0] gn,

	// buttons for user io
	input wire [6:0] btn
);

	// gpio0 must be tied high to prevent board from rebooting
	assign wifi_gpio0 = 1;
	
	assign user_programn = 1;

        // button 0 is the power and is negative logic
	// hold it in to reboot the board to the bootloader.
	// however this causes problems if the RV3 resistor is removed,
	// so we're using button 6 ("right") instead, which is normal logic
	// user_programn is inverted
	/*wire user_reboot;
        reg [7:0] reboot;
        assign user_programn = !(reboot[7] || user_reboot);
        always @(posedge clk_25mhz) reboot <= btn[6] ? reboot + 1 : 0;*/
	
	wire clk_133, locked;
	wire reset = !locked || btn[1];
	pll_133 pll_133_i(clk_25mhz, clk_133, locked);
	wire clk = clk_133;
	assign sdram_clk = clk_133;
	
	// ---
	
	wire[63:0] sdram_read_buffer;
	wire sdram_read_busy;

	wire[63:0] sdram_write_buffer;
    //wire[7:0] sdram_write_mask;

	// --- SPI --------------------------------------------
	
	// SPI bus is on the left-side headers, positive pins
	// these have the voltage selected by the RV3 resistor and header
	wire spi_cs_pin = gp[22];
	//wire spi_clk_pin = gp[21];
	wire spi_clk_pin = gp[17];
	wire spi_mosi_pin = gp[23];
	//wire spi_miso_pin = gp[19]; // FAKE MISO
	wire spi_miso_pin = gp[24];
	wire spi_power_pin = gp[25];
	
	wire spi_debug_pin = gp[20];
	wire spi_debug_out;
	
	wire spi_debug2_pin = gp[19];
	wire spi_debug2_out;
	
	wire spi_miso_enable;
	wire spi_miso_out;
	wire spi_mosi_in;
	wire spi_clk_in;
	wire spi_cs_in;
	wire spi_power_in;

	//wire spi_reset = reset;
	
	IB spi_cs_buf(
        .I(spi_cs_pin),
        .O(spi_cs_in)
    );
	OBZ spi_miso_buf(
        .T(!(spi_miso_enable && (!spi_cs_in) && spi_power_in)),
        .O(spi_miso_pin),
        .I(spi_miso_out)
    );
	IB spi_mosi_buf(
		.I(spi_mosi_pin),
		.O(spi_mosi_in)
	);
	IB spi_clk_buf(
		.I(spi_clk_pin),
		.O(spi_clk_in)
	);
	IB spi_power_buf(
		.I(spi_power_pin),
		.O(spi_power_in)
	);
	OB spi_debug_buf(
		.O(spi_debug_pin),
		.I(spi_debug_out)
	);
	OB spi_debug2_buf(
		.O(spi_debug2_pin),
		.I(spi_debug2_out)
	);
	
	reg[1:0] spi_power_reg;
	//always @(posedge clk) spi_power_reg <= {spi_power_reg[0], spi_power_in};
	
	reg spi_reset;
	reg[16:0] spi_reset_count;
	
	always @(posedge clk) begin
		spi_power_reg <= {spi_power_reg[0], spi_power_in};
		
		if ((!reset) && spi_power_reg[1]) begin
			if (spi_reset && spi_reset_count[16]) begin
				spi_reset <= 0;
				spi_reset_count <= 0;
			end
			else
				spi_reset_count <= spi_reset_count + 1;
		end
		else begin
			spi_reset <= 1;
			spi_reset_count <= 0;
		end
	end
	
	wire spi_active;
	
	wire spi_ram_inhibit_refresh;
	wire spi_ram_activate;
	wire spi_ram_read;
	
	wire[21:0] spi_ram_addr;
	
	wire spi_write_cmd;
	wire spi_write_type;
	wire[21:0] spi_write_addr;
	wire[12:0] spi_write_len;
	wire spi_write_done;
	
	wire spi_write_buf_strobe;
	wire[7:0] spi_write_buf_offset;
	wire[7:0] spi_write_buf_val;
	
	wire log_strobe;
	wire[7:0] log_val;
	
	spi_trx spi_trx_i(
		.clk(clk),
		
		.spi_clk(spi_clk_in),
		.spi_reset(spi_reset),
		.spi_csel(spi_cs_in),
		.spi_mosi(spi_mosi_in),
		.spi_miso(spi_miso_out),
		.spi_miso_enable(spi_miso_enable),
		//.spi_power(spi_power_in),
		//.spi_power(spi_power_reg[1]),
		.spi_debug(spi_debug_out),
		
		.spi_active(spi_active),
		
		.ram_inhibit_refresh(spi_ram_inhibit_refresh),
		.ram_activate(spi_ram_activate),
		.ram_read(spi_ram_read),
		
		.ram_addr(spi_ram_addr),
		.ram_read_buffer(sdram_read_buffer),
		.ram_read_busy(sdram_read_busy),
		
		.write_cmd(spi_write_cmd),
		.write_type(spi_write_type),
		.write_addr(spi_write_addr),
		.write_len(spi_write_len),
		.write_done(spi_write_done),
		
		.write_buf_strobe(spi_write_buf_strobe),
		.write_buf_offset(spi_write_buf_offset),
		.write_buf_val(spi_write_buf_val),
		
		.log_strobe(log_strobe),
		.log_val(log_val)
	);
	
	// --- SDRAM ------------------------------------------

	wire[15:0] sdram_dq_o;
	wire[15:0] sdram_dq_i;
	wire sdram_dq_oe;

	// the dq pins are bidirectional and controlled by the dq_oe signal
	genvar i;
	generate
	for (i = 0; i < 16; i = i+1)
		begin
		BB sdram_d_buf(
			.T(!sdram_dq_oe),
			.B(sdram_d[i]),
			.I(sdram_dq_o[i]),
			.O(sdram_dq_i[i])
		);
		end
	endgenerate

	wire[2:0] sdram_cmd = {sdram_rasn, sdram_casn, sdram_wen};

	wire[1:0] sdram_access_cmd;
	wire[23:0] sdram_access_addr;
	wire sdram_inhibit_refresh;
	wire sdram_cmd_busy;
	
	//wire[3:0] sdram_debug;

	sdram #(
		.CLK_FREQ_MHZ(133),
		.BURST_LEN(4)
	) sdram_i (
		.clk(clk),
		.reset(reset),

		.ba_o(sdram_ba),
		.a_o(sdram_a),
		.cs_o(sdram_csn),
		.cmd_o(sdram_cmd),
		.dq_i(sdram_dq_i),
		.dq_o(sdram_dq_o),
		.dqm_o(sdram_dqm),
		.dq_oe_o(sdram_dq_oe),
		.cke_o(sdram_cke),
		
		.spi_inhibit_refresh(spi_ram_inhibit_refresh),
		.spi_cmd_activate(spi_ram_activate),
		.spi_cmd_read(spi_ram_read),
		.spi_addr(spi_ram_addr),

		.access_cmd(sdram_access_cmd),
		.access_addr(sdram_access_addr),
		.inhibit_refresh(sdram_inhibit_refresh),
		.cmd_busy(sdram_cmd_busy),

		.read_buffer(sdram_read_buffer),
		.read_busy(sdram_read_busy),

		.write_buffer(sdram_write_buffer)//,
		//.write_mask(sdram_write_mask)
	);



	// serial fifo, either usb serial or ftdi serial
	wire uart_txd_ready;
	wire [7:0] uart_txd;
	wire uart_txd_strobe;
	wire uart_rxd_strobe;
	wire [7:0] uart_rxd;
	
//`define USB_SERIAL
	
`ifdef USB_SERIAL

	wire clk_48;
	pll_48 pll_48_i(clk_133, clk_48);

	wire usb_tx_en;
	wire usb_n_in, usb_n_out;
	wire usb_p_in, usb_p_out;
	assign usb_fpga_pu_dp = 1; // full speed 1.1 device
	assign usb_fpga_pu_dn = 0; // full speed 1.1 device
	//assign ftdi_rxd = 1; // idle high
	
	BB usb_p_buf(
		.T(!usb_tx_en),
		.B(usb_fpga_bd_dp),
		.I(usb_p_out),
		.O(usb_p_in)
	);
	BB usb_n_buf(
		.T(!usb_tx_en),
		.B(usb_fpga_bd_dn),
		.I(usb_n_out),
		.O(usb_n_in)
	);

	usb_serial usb_serial_i(
		.clk_48mhz(clk_48),
		.clk(clk),
		.reset(reset),
		// physical
		.usb_p_tx(usb_p_out),
		.usb_n_tx(usb_n_out),
		.usb_p_rx(usb_tx_en ? 1'b1 : usb_p_in),
		.usb_n_rx(usb_tx_en ? 1'b0 : usb_n_in),
		.usb_tx_en(usb_tx_en),
		// logical
		.uart_tx_ready(uart_txd_ready),
		.uart_tx_data(uart_txd),
		.uart_tx_strobe(uart_txd_strobe),
		
		.uart_rx_data(uart_rxd),
		.uart_rx_strobe(uart_rxd_strobe)
		// .host_presence (not used)
	);

`else

	// ftdi serial port interface for talking to the host system
	uart #(
		.DIVISOR(133 / 3),
		.FIFO(256),
		//.FIFO(16),
		.FREESPACE(16)
		//.FREESPACE(1)
	) uart_i(
		.clk(clk),
		.reset(reset),
		// physical
		.serial_txd(ftdi_rxd), // fpga --> ftdi
		.serial_rxd(ftdi_txd), // fpga <-- ftdi
		// logical
		.txd(uart_txd),
		.txd_strobe(uart_txd_strobe),
		// use this for our outputs
		.txd_ready(uart_txd_ready),
		.rxd(uart_rxd),
		.rxd_strobe(uart_rxd_strobe)
	);
	
`endif
	
	glue glue_i(
		.clk(clk),
		.reset(reset),

		.rxd_strobe(uart_rxd_strobe),
		.rxd_data(uart_rxd),

		.txd_ready(uart_txd_ready),
		.txd_strobe(uart_txd_strobe),
		.txd_data(uart_txd),

		.sdram_access_cmd(sdram_access_cmd),
		.sdram_access_addr(sdram_access_addr),
		.sdram_inhibit_refresh(sdram_inhibit_refresh),
		.sdram_cmd_busy(sdram_cmd_busy),

		.sdram_read_buffer(sdram_read_buffer),
		.sdram_read_busy(sdram_read_busy),

		.sdram_write_buffer(sdram_write_buffer),
		//.sdram_write_mask(sdram_write_mask),
		
		.spi_reset(spi_reset),
		.spi_csel(spi_cs_in),
		
		.spi_cmd_write(spi_write_cmd),
		.spi_write_type(spi_write_type),
		.spi_write_addr(spi_write_addr),
		.spi_write_len(spi_write_len),
		.spi_write_done(spi_write_done),
		
		.spi_write_buf_strobe(spi_write_buf_strobe),
		.spi_write_buf_offset(spi_write_buf_offset),
		.spi_write_buf_val(spi_write_buf_val),
		
		.log_strobe(log_strobe),
		.log_val(log_val),

		.led(led)//,
		//.debug(spi_debug2_out)
	);

endmodule

