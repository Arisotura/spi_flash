// low-level SPI transmit/receive module

module spi_trx(
    input wire clk,

    input wire spi_clk,
    input wire spi_reset,    // active high
    input wire spi_csel,     // active low
    input wire spi_mosi,
    output reg spi_miso = 0,
	output reg spi_miso_enable = 0,
	output reg spi_debug = 0,
	
	output wire spi_active,
	
	// SDRAM control signals
	output reg ram_inhibit_refresh = 0,
	output reg ram_activate = 0,
	output reg ram_read = 0,
	
	output reg[21:0] ram_addr,
	input wire[63:0] ram_read_buffer,
	input wire ram_read_busy,
	
	output reg log_strobe = 0,
	output reg[7:0] log_val = 0
);

    wire is_selected = (!spi_reset) && (!spi_csel);
	
	assign spi_active = is_selected;
	
	// reset detect
	// the issue is that we run off the SPI clock, but these conditions
	// typically happen while the SPI clock is idle
	// manually instantiating flipflops allows us to reliably detect them
	
	wire reset_cs;
	wire reset_power;

	FD1P3BX reset_ff(
		.D(0),
		.SP(is_selected),
		.CK(spi_clk),
		.PD(!is_selected),
		.Q(reset_cs)
	);
	
	FD1P3BX power_ff(
		.D(0),
		.SP(is_selected),
		.CK(spi_clk),
		.PD(spi_reset),
		.Q(reset_power)
	);

    reg[2:0] bit_count_in;

    reg[7:0] mosi_byte;
    reg[7:0] miso_byte;
	
	reg[23:0] jedec_id = {8'h19, 8'hBA, 8'h20};
	
	localparam
		CMD_READ			= 8'h03,
		CMD_WRITEDISABLE	= 8'h04,
		CMD_READSTATUS		= 8'h05,
		CMD_WRITEENABLE		= 8'h06,
		CMD_READID1			= 8'h9E,
		CMD_READID2			= 8'h9F,
		CMD_4BYTEENABLE		= 8'hB7,
		CMD_4BYTEDISABLE	= 8'hE9,
		CMD_LOG				= 8'hF2;
	
	localparam
		STA_CMD			= 0, // receiving command byte
		STA_READSTATUS	= 1, // reading status register
		STA_ADDR_READ	= 2, // receiving address for a read command
		STA_READ		= 3, // sending out bytes for a read command
		STA_READID		= 4, // reading JEDEC ID
		STA_LOG			= 5; // logging (passthrough to serial)
	
	reg[3:0] state;
	
	reg[31:0] addr;
	reg[4:0] addr_count;
	reg addr_4byte;
	
	wire[2:0] byte_addr_on_a0 = {addr[2:1], spi_mosi};
	
	reg fresh_read = 0;
	
	//reg[3:0] darp = 0;
	
	// bit1 = write enable latch
	// bit0 = write in progress
	reg[7:0] status_reg = 8'b00000000;

    always @(posedge spi_clk) begin
		if (is_selected) begin
			fresh_read <= 0;
			
			spi_debug <= 0;
			
			if (reset_cs || reset_power) begin
				// starting a new command -- reinitialize state

				bit_count_in <= 6;
				mosi_byte <= {spi_mosi, 7'b0};
				miso_byte <= 0;
				
				spi_miso_enable <= 0;
				
				state <= STA_CMD;
				
				addr <= 0;
				addr_count <= 0;
				
				log_strobe <= 0;
				log_val <= 0;
				
				ram_inhibit_refresh <= 0;
				ram_activate <= 0;
				ram_read <= 0;
				
				if (reset_power) begin
					// if we received a reset, reset some internal registers
					
					status_reg[1:0] <= 2'b00;
					addr_4byte <= 0;
					
					log_strobe <= 1;
					log_val <= 8'hE2;
					
					//darp <= 0;
				end
			end
			else begin
				log_strobe <= 0;
				
				// sample MOSI, advance bit count
				mosi_byte[bit_count_in] <= spi_mosi;
				
				//if (bit_count_in == 7 && state == STA_CMD)
				//	spi_debug <= 1;

				if ((state == STA_CMD) && (bit_count_in == 0)) begin
					// we received a full command byte
					
					case ({mosi_byte[7:1], spi_mosi})
						
					CMD_READSTATUS: begin
						state <= STA_READSTATUS;
						spi_miso_enable <= 1;
						miso_byte <= status_reg;
					end
					
					CMD_WRITEDISABLE: begin
						status_reg[1] <= 0;
					end
					
					CMD_WRITEENABLE: begin
						status_reg[1] <= 1;
					end
					
					CMD_4BYTEENABLE: begin
						if (status_reg[1]) addr_4byte <= 1;
					end
					
					CMD_4BYTEDISABLE: begin
						if (status_reg[1]) addr_4byte <= 0;
					end
						
					CMD_READ: begin
						state <= STA_ADDR_READ;
						
						addr_count <= addr_4byte ? 31 : 23;
					end
					
					CMD_READID1,
					CMD_READID2: begin
						state <= STA_READID;
						
						spi_miso_enable <= 1;
						miso_byte <= jedec_id[7:0];
						addr_count <= 1;
					end
					
					CMD_LOG: begin
						state <= STA_LOG;
					end
						
					endcase
					
					log_strobe <= 1;
					log_val <= {mosi_byte[7:1], spi_mosi};
				end
				else if ((state == STA_READSTATUS) && (bit_count_in == 0)) begin
					miso_byte <= status_reg;
				end
				else if (state == STA_ADDR_READ) begin
					// when receiving address bytes for a read,
					// signal various points of interest:
					// * bit7: inhibit SDRAM refresh
					// * bit4: send SDRAM activate command
					// * bit3: send SDRAM read command
					// * bit0: read out the desired byte
					
					if (addr_count == 7) begin
						ram_inhibit_refresh <= 1;
					end
					else if (addr_count == 4) begin
						ram_activate <= 1;
						ram_addr[21:7] <= addr[24:10];
					end
					else if (addr_count == 3) begin
						ram_read <= 1;
						ram_addr[6:0] <= {addr[9:4], spi_mosi};
					end
					else if (addr_count == 0) begin
						state <= STA_READ;
						spi_miso_enable <= 1;

						ram_inhibit_refresh <= 0;
						ram_activate <= 0;
						ram_read <= 0;
							
						fresh_read <= 1;
						
						//darp <= darp+1;
						//if (addr == 31'h005000B4)
						//if (darp == 4)
							spi_debug <= 1;
					end
					
					if (bit_count_in == 0) begin
						log_strobe <= 1;
						log_val <= {mosi_byte[7:1], spi_mosi};
					end
					
					addr[addr_count] <= spi_mosi;
					addr_count <= addr_count - 1;
				end
				else if (state == STA_READ) begin
					// advance the read
					
					if (addr[2:0] == 7) begin
						// reaching the end of the last burst, we need to start reading a new one
						
						if (bit_count_in == 7) begin
							ram_inhibit_refresh <= 1;
						end
						else if (bit_count_in == 4) begin
							ram_activate <= 1;
							ram_addr <= ram_addr + 1;
						end
						else if (bit_count_in == 3) begin
							ram_read <= 1;
						end
						else if (bit_count_in == 0) begin
							ram_inhibit_refresh <= 0;
							ram_activate <= 0;
							ram_read <= 0;
							
							fresh_read <= 1;
						end
					end
					
					if (bit_count_in == 0) begin
						miso_byte <= ram_read_buffer[(addr[2:0]+1)*8+:8];
						addr <= addr + 1;
					end
					
					if (fresh_read) 
						miso_byte <= ram_read_buffer[addr[2:0]*8+:8];
				end
				else if (state == STA_READID) begin
					if (bit_count_in == 0) begin
						if (addr_count < 3) begin
							miso_byte <= jedec_id[addr_count*8+:8];
							addr_count <= addr_count + 1;
						end
						else
							miso_byte <= 0;
					end
				end
				else if (state == STA_LOG) begin
					if (bit_count_in == 0) begin
						log_strobe <= 1;
						log_val <= {mosi_byte[7:1], spi_mosi};
					end
				end
				
				bit_count_in <= bit_count_in - 1;
			end
		end
    end
	
	always @(negedge spi_clk) begin
		if (fresh_read)
			spi_miso <= ram_read_buffer[addr[2:0]*8+7];
		else
			spi_miso <= miso_byte[bit_count_in];
	end

endmodule
