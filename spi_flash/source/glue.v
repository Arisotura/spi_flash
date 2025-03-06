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
	
	//input wire[3:0] sdram_debug,
	
	// SPI signals
	input wire spi_reset,
	input wire spi_csel,
	
	input wire spi_cmd_write,
	input wire spi_write_type,	// 0=write 1=erase
	input wire[21:0] spi_write_addr,
	input wire[12:0] spi_write_len,
	output reg spi_write_done,
	
	input wire spi_write_buf_strobe,
	input wire[7:0] spi_write_buf_offset,
	input wire[7:0] spi_write_buf_val,
	
	input wire log_strobe,
	input wire[7:0] log_val,
	
    output reg[7:0] led//,
	//output reg debug
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
	
	reg[1:0] spi_csel_buf;
	
	reg spi_writing;
	reg spi_write_ack;
	reg[1:0] spi_cmd_write_buf;
	
	reg i_spi_write_type;
	reg[2:0] i_spi_write_state;
	reg[12:0] i_spi_len;
	
	reg[8:0] i_spi_write_data[0:255];
	reg[1:0] spi_write_buf_strobe_buf;
	reg spi_write_buf_ack;
	
	integer i;

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
            sdram_inhibit_refresh <= 0;

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
			
			spi_write_buf_strobe_buf <= 0;
			spi_write_buf_ack <= 0;

			for (i = 0; i < 256; i=i+1)
				i_spi_write_data[i][8] <= 0;
        end
        else begin
            txd_strobe_buf <= 0;
            txd_strobe <= txd_strobe_buf;
            txd_data <= txd_data_buf;
			
			rxd_strobe_buf <= rxd_strobe;
			rxd_data_buf <= rxd_data;
			
			sdram_access_addr <= {addr, 2'b0};
			//read_buffer <= sdram_read_buffer;
			sdram_write_buffer <= write_buffer;
			sdram_inhibit_refresh <= 0;
	
            if (sdram_access_cmd)
                sdram_access_cmd <= 0;
				
			spi_csel_buf <= {spi_csel_buf[0], spi_csel};

			led[7] <= (!spi_reset) && (!spi_csel_buf[1]);
			led[6] <= sdram_cmd_busy;
			led[5] <= spi_writing;
			
			if (log_strobe_buf[1] && (!log_ack)) begin
				txd_strobe_buf <= 1;
				txd_data_buf <= log_val;
				log_ack <= 1;
			end
			if (!log_strobe_buf[1]) log_ack <= 0;
				
				
			spi_write_buf_strobe_buf <= {spi_write_buf_strobe_buf[0], spi_write_buf_strobe};
			
			if (!spi_write_buf_strobe_buf[1])
				spi_write_buf_ack <= 0;
				
			if (spi_write_buf_strobe_buf[1] && (!spi_write_buf_ack)) begin
				// store data in the buffer for page program operations
				i_spi_write_data[spi_write_buf_offset] <= {1'b1, spi_write_buf_val};
				spi_write_buf_ack <= 1;
			end
			
				
			spi_cmd_write_buf <= {spi_cmd_write_buf[0], spi_cmd_write};
			
			if (!spi_cmd_write_buf[1])
				spi_write_ack <= 0;

			if (spi_cmd_write_buf[1] && (!spi_write_ack) && spi_csel_buf[1]) begin
				spi_writing <= 1;
				spi_write_ack <= 1;
				
				i_spi_write_type <= spi_write_type;
				i_spi_write_state <= spi_write_type ? 3 : 0;
				
				addr <= spi_write_addr;
				i_spi_len <= spi_write_len;
				spi_write_done <= 0;
				
				if (spi_write_type)
					write_buffer <= 64'hFFFFFFFFFFFFFFFF;
			end
			
			if (spi_writing && (!sdram_busy)) begin
				// handle SPI write

				if (i_spi_write_state == 0) begin
					// activate for read
					sdram_access_cmd <= 2'b11;
					
					// prepare data
					for (i = 0; i < 8; i=i+1) begin
						write_buffer[i*8+:8] <= i_spi_write_data[addr[4:0]*8+i][7:0];
						write_mask[i] <= i_spi_write_data[addr[4:0]*8+i][8];
						i_spi_write_data[addr[4:0]*8+i][8] <= 0;
					end

					i_spi_write_state <= 1;
				end
				else if (i_spi_write_state == 1) begin
					// read
					sdram_access_cmd <= 2'b01;

					i_spi_write_state <= 2;
				end
				else if (i_spi_write_state == 2) begin
					// modify
					for (i = 0; i < 8; i=i+1) begin
						if (!write_mask[i])
							write_buffer[i*8+:8] <= sdram_read_buffer[i*8+:8];
					end

					i_spi_write_state <= 3;
				end
				
				if (i_spi_write_state == 3) begin
					// activate for write
					sdram_access_cmd <= 2'b11;

					i_spi_write_state <= 4;
				end
				else if (i_spi_write_state == 4) begin
					// write
					sdram_access_cmd <= 2'b10;

					i_spi_write_state <= 5;
				end
				else if (i_spi_write_state == 5) begin

					if (i_spi_len == 0) begin
						// finished
						spi_writing <= 0;
						spi_write_done <= 1;
					end
					else begin
						// prepare for the next burst
						i_spi_write_state <= spi_write_type ? 3 : 0;
						
						addr <= addr + 1;
						i_spi_len <= i_spi_len - 1;
					end
				end
			end
            
			if (spi_reset || spi_csel_buf[1]) begin
				
				if (rxd_strobe_buf) begin

					if (in_count == 0) begin
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
							
							write_buffer[write_pos*8+:8] <= rxd_data_buf;
							
							if (write_pos == 7) begin
								write_strobe <= 1;
							end

							write_pos <= write_pos+1;

						end

						if (in_count <= 4)
							in_count <= in_count + 1;
					end

				end
				else begin

					if (write_strobe && (!sdram_busy))
						write_state <= 1;

					if (read_state) begin
						if ((read_state == 1) && (!sdram_busy)) begin
							// activate
							sdram_access_cmd <= 2'b11;

							read_state <= 2;
						end
						else if ((read_state == 2) && (!sdram_busy)) begin
							// read
							sdram_access_cmd <= 2'b01;

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

							write_strobe <= 0;
							write_state <= 2;
						end
						else if ((write_state == 2) && (!sdram_busy)) begin
							// write
							sdram_access_cmd <= 2'b10;

							write_state <= 3;
						end
						else if ((write_state == 3) && (!sdram_busy)) begin

							if (len == 1) begin
								if (txd_ready) begin
									// finished
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
