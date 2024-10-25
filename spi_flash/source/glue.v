// 'glue' module

module glue(
    input wire clk,
    input wire reset,

    input wire rxd_strobe,
    input wire[7:0] rxd_data,

    input wire txd_ready,
    output reg txd_strobe,
    output reg[7:0] txd_data,

    // SDRAM control signals
    output reg[1:0] sdram_access_cmd, // 00=nop 01=read 10=write 11=activate
    output reg[23:0] sdram_access_addr,
    output reg sdram_inhibit_refresh,
    input wire sdram_cmd_busy,

    input wire[63:0] sdram_read_buffer,
	input wire sdram_read_busy,

    output reg[63:0] sdram_write_buffer,
    output reg[7:0] sdram_write_mask,
	
	input wire[3:0] sdram_debug,
	
	// SPI signals
	input wire spi_active,
	
	input wire spi_cmd_write,
	input wire spi_write_type,	// 0=write 1=erase
	input wire[21:0] spi_write_addr,
	input wire[12:0] spi_write_len,
	output reg spi_write_done,
	
	input wire log_strobe,
	input wire[7:0] log_val,
	
	//input wire[1:0] farto,

    output reg[7:0] led
);

    localparam
        CMD_NOP          = 8'h00,
        CMD_VERSION      = 8'h30,
        CMD_RAMREAD      = 8'h31,
        CMD_RAMWRITE     = 8'h32;

    localparam VERSION = 8'h01;

    reg[7:0] cmd;
    reg[3:0] in_count;

    reg[21:0] addr;
	reg[7:0] len;
    //reg[24:0] len;

    //reg[55:0] debug;

    reg[2:0] read_state;
    reg[2:0] read_pos;

    reg[2:0] write_state;
    reg[2:0] write_pos;

    reg txd_strobe_buf;
    reg[7:0] txd_data_buf;
	
	reg rxd_strobe_buf;
	reg[7:0] rxd_data_buf;

    wire sdram_busy = (sdram_access_cmd != 0) || sdram_cmd_busy;
	
	reg[63:0] write_buffer;
    reg[7:0] write_mask;
	reg write_strobe;
	
	reg[1:0] log_strobe_buf;
	always @(posedge clk) log_strobe_buf <= {log_strobe_buf[0], log_strobe};
	reg log_ack;
	
	reg spi_writing;
	reg spi_write_ack;
	reg[1:0] spi_cmd_write_buf;
	
	reg i_spi_write_type;
	reg[1:0] i_spi_write_state;
	reg[21:0] i_spi_addr;
	reg[12:0] i_spi_len;

    always @(posedge clk)
    begin
        if (reset) begin
            cmd <= CMD_NOP;
            in_count <= 0;
            addr <= 0;
            len <= 0;

            read_state <= 0;
            read_pos <= 0;

            write_state <= 0;
            write_pos <= 0;

            sdram_access_cmd <= 0;
            sdram_access_addr <= 0;
            sdram_inhibit_refresh <= 0;

            sdram_write_buffer <= 0;
            sdram_write_mask <= 16'hFFFF;
			
			write_buffer <= 0;
			write_mask <= 16'hFFFF;
			write_strobe <= 0;

            txd_strobe_buf <= 0;
            txd_data_buf <= 0;
			
			rxd_strobe_buf <= 0;
            rxd_data_buf <= 0;
			
			led <= 0;
			log_ack <= 0;
			
			spi_writing <= 0;
			spi_write_ack <= 0;
			spi_cmd_write_buf <= 0;
			spi_write_done <= 0;
			
			/*i_spi_write_type <= 0;
			i_spi_write_state <= 0;
			i_spi_addr <= 0;
			i_spi_len <= 0;*/
        end
        else begin
            txd_strobe_buf <= 0;
            txd_strobe <= txd_strobe_buf;
            txd_data <= txd_data_buf;
			
			rxd_strobe_buf <= rxd_strobe;
			rxd_data_buf <= rxd_data;

            if (sdram_access_cmd)
                sdram_access_cmd <= 0;

			led[7] <= spi_active;
			led[6] <= sdram_cmd_busy;
			//led[2:0] <= write_state;
			//led[5:3] <= write_pos;
			//led[5:4] <= farto;
			
			/*if (sdram_debug[3]) begin
				txd_strobe_buf <= 1;
				txd_data_buf <= {4'h7, sdram_debug};
			end
			else*/
			if (log_strobe_buf[1] && (!log_ack)) begin
				txd_strobe_buf <= 1;
				txd_data_buf <= log_val;
				log_ack <= 1;
			end
			if (!log_strobe_buf[1]) log_ack <= 0;
				
			spi_cmd_write_buf <= {spi_cmd_write_buf[0], spi_cmd_write};
			
			if (!spi_cmd_write_buf[1])
				spi_write_ack <= 0;

			if (spi_cmd_write_buf[1] && (!spi_write_ack)) begin
				spi_writing <= 1;
				spi_write_ack <= 1;
				i_spi_write_type <= spi_write_type;
				i_spi_write_state <= 0;
				i_spi_addr <= spi_write_addr;
				i_spi_len <= spi_write_len;
				spi_write_done <= 0;
			end
			else if (spi_writing) begin
				// handle SPI write
				
				if (i_spi_write_type == 0) begin
					// write
					// if (len[15:3])
					// sdram_write_mask <= (16'hFFFF << len[2:0]);
				end
				else begin
					// erase
					
					if ((i_spi_write_state == 0) && (!sdram_busy)) begin
						// activate
						sdram_access_cmd <= 2'b11;
						sdram_access_addr <= {i_spi_addr, 2'b0};

						i_spi_write_state <= 1;
					end
					else if ((i_spi_write_state == 1) && (!sdram_busy)) begin
						// write
						sdram_access_cmd <= 2'b10;
						sdram_access_addr <= {i_spi_addr, 2'b0};
						
						sdram_write_buffer <= 64'hFFFFFFFFFFFFFFFF;
						sdram_write_mask <= 16'h0000;

						i_spi_write_state <= 2;
					end
					else if ((i_spi_write_state == 2) && (!sdram_busy)) begin

						if (i_spi_len == 0) begin
							// finished
							spi_writing <= 0;
							spi_write_done <= 1;
						end
						else begin
							// prepare for the next burst
							i_spi_write_state <= 0;
							
							i_spi_addr <= i_spi_addr + 1;
							i_spi_len <= i_spi_len - 1;
						end
					end
				end
				
			end
            else if (!spi_active) begin
				sdram_inhibit_refresh <= 0;
				
				if (rxd_strobe_buf) begin
					//led[7] <= 1;

					if (in_count == 0) begin
						//if (rxd_data_buf) led <= rxd_data_buf;
						if (rxd_data_buf == CMD_VERSION) begin
							txd_strobe_buf <= 1;
							txd_data_buf <= VERSION;
							in_count <= 0;
						end
						else if (rxd_data_buf == CMD_RAMREAD ||
								 rxd_data_buf == CMD_RAMWRITE) begin
							cmd <= rxd_data_buf;
							in_count <= 1;

							read_state <= 0;
							read_pos <= 0;

							write_state <= 0;
							write_pos <= 0;
						end
					end
					else begin
						if (in_count <= 3) // input bytes 0..3
							addr <= {addr[13:0], rxd_data_buf};
						else if (in_count == 4)
							len <= rxd_data_buf;

						if (cmd == CMD_RAMREAD && in_count == 4) begin

							read_state <= 1;

						end
						if (cmd == CMD_RAMWRITE && in_count > 4) begin
							//led[6] <= 1;
							write_buffer[write_pos*8+:8] <= rxd_data_buf;
							write_mask[write_pos] <= 0;

							if (write_pos == 7) begin
								//if (write_strobe) led[0] <= 1;
								write_strobe <= 1;
							end

							write_pos <= write_pos+1;

						end

						if (in_count <= 4)
							in_count <= in_count + 1;
					end

				end
				else begin
					//txd_strobe <= 0;
					
					if (write_strobe && (!sdram_busy))
						write_state <= 1;

					if (read_state) begin
						if ((read_state == 1) && (!sdram_busy)) begin
							// activate
							sdram_access_cmd <= 2'b11;
							sdram_access_addr <= {addr, 2'b0};

							read_state <= 2;
						end
						else if ((read_state == 2) && (!sdram_busy)) begin
							// read
							sdram_access_cmd <= 2'b01;
							sdram_access_addr <= {addr, 2'b0};

							read_state <= 3;
						end
						else if ((read_state == 3) && (!sdram_busy) && txd_ready) begin
							txd_strobe_buf <= 1;
							txd_data_buf <= sdram_read_buffer[read_pos*8+:8];

							if (read_pos == 7) begin
								// end of burst
								
								if (len == 1) begin
									// end of read
									read_state <= 0;
									in_count <= 0;
									cmd <= CMD_NOP;
								end
								else begin
									// start next burst
									addr <= addr + 1;
									len <= len - 1;
									
									read_state <= 1;
									read_pos <= 0;
								end
							end
							else
								read_pos <= read_pos + 1;
						end
					end
					else if (write_state) begin
						// commit write to SDRAM
						if ((write_state == 1) && (!sdram_busy)) begin
							// activate
							sdram_access_cmd <= 2'b11;
							sdram_access_addr <= {addr, 2'b0};
							
							write_strobe <= 0;

							write_state <= 2;
						end
						else if ((write_state == 2) && (!sdram_busy)) begin
							// write
							sdram_access_cmd <= 2'b10;
							sdram_access_addr <= {addr, 2'b0};
							
							sdram_write_buffer <= write_buffer;
							sdram_write_mask <= write_mask;
							write_buffer <= 0;
							write_mask <= 16'hFFFF;

							write_state <= 3;
						end
						else if ((write_state == 3) && (!sdram_busy)) begin

							if (len == 1) begin
								//led[1] <= 1;
								if (txd_ready) begin
									// finished
									//led[2] <= 1;
									txd_strobe_buf <= 1;
									txd_data_buf <= 8'h01;

									write_state <= 0;
									in_count <= 0;
									cmd <= CMD_NOP;
								end
							end
							else begin
								// prepare for the next burst
								write_state <= 0;
								//led[3] <= 1;
								
								addr <= addr + 1;
								len <= len - 1;
							end
						end
					end
				end
			end
        end
    end

endmodule
