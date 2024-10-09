// usage-specific SDRAM controller

module sdram(
    input wire clk,
    input wire reset,

    // SDRAM interface
    output reg[1:0] ba_o,
    output reg[12:0]  a_o,
    output reg cs_o,
    output reg[2:0] cmd_o,
    output reg[15:0] dq_o,
    output reg[1:0] dqm_o,
    input wire[15:0] dq_i,
    output reg dq_oe_o,
    output reg cke_o,
	
	// control signals from spi_trx
	input wire spi_inhibit_refresh,
	input wire spi_cmd_activate,
	input wire spi_cmd_read,
	input wire[21:0] spi_addr,

    // control signals
	// TODO use separate lines instead of binary cmd?
    input wire[1:0] access_cmd, // 00=nop 01=read 10=write 11=activate
    input wire[23:0] access_addr, // access address (in 16bit units)
    input wire inhibit_refresh,
    output reg cmd_busy,

    output reg[(BURST_LEN*16)-1:0] read_buffer,
	output reg read_busy,

    input wire[(BURST_LEN*16)-1:0] write_buffer,
    input wire[(BURST_LEN*2)-1:0] write_mask
);

    parameter CLK_FREQ_MHZ = 125;

`define MAX(a,b) ((a) > (b) ? (a) : (b))

    parameter BURST_LEN = 4;
    localparam BURST_MODE =
        (BURST_LEN == 1) ? 3'b000 :
        (BURST_LEN == 2) ? 3'b001 :
        (BURST_LEN == 4) ? 3'b010 :
        (BURST_LEN == 8) ? 3'b011 :
        3'b111;
		
	// TODO use this and not hardcode addr width
	localparam ADDR_WIDTH =
        (BURST_LEN == 1) ? 24 :
        (BURST_LEN == 2) ? 23 :
        (BURST_LEN == 4) ? 22 :
        (BURST_LEN == 8) ? 21 :
        25;

    localparam integer tINIT        = 100 * CLK_FREQ_MHZ;
    //localparam integer tREFRESH     = (CLK_FREQ_MHZ * 63000) / 8192;
    localparam integer tREFRESH     = (CLK_FREQ_MHZ * 32000) / 8192;
    localparam integer tRP          = $ceil(0.015 * CLK_FREQ_MHZ);
    localparam integer tRC          = $ceil(0.060 * CLK_FREQ_MHZ);
    localparam integer tMRD         = $ceil(0.014 * CLK_FREQ_MHZ);
    localparam integer tRCD         = $ceil(0.015 * CLK_FREQ_MHZ);
    localparam integer tDPL         = $ceil(0.014 * CLK_FREQ_MHZ);
    localparam integer tRAS         = $ceil(0.037 * CLK_FREQ_MHZ);
    localparam integer tCAS         = 2;
    localparam integer tREAD        = `MAX(tCAS+BURST_LEN, `MAX(tRAS+tRP,tRC)-tRCD);
    localparam integer tWRITE       = `MAX((BURST_LEN-1)+tDPL+tRP, `MAX(tRAS+tRP,tRC)-tRCD);

    localparam
        STA_INIT            = 0,
        STA_INIT_PRECHARGE  = 1,
        STA_INIT_REFRESH    = 2,
        STA_IDLE            = 3,
        STA_SETMODE         = 4,
        STA_REFRESH         = 5,
        STA_ACTIVATE        = 6,
        STA_READ            = 7,
        STA_WRITE           = 8;

    localparam
        CMD_NOP         = 3'b111,
        CMD_BURST_STOP  = 3'b110,
        CMD_READ        = 3'b101,
        CMD_WRITE       = 3'b100,
        CMD_ACTIVATE    = 3'b011,
        CMD_PRECHARGE   = 3'b010,
        CMD_REFRESH     = 3'b001,
        CMD_SETMODE     = 3'b000;

    reg[3:0] state;

    reg[$clog2(tINIT)-1:0] initcount;
    reg initrefreshcount;

    reg[3:0] cmdcount;
    reg[3:0] cmdtarget;

    reg[$clog2(tREFRESH):0] refreshcount;
	
	// the control signals from spi_trx come from a different clock domain
	// so they have to be buffered to be reliable
	reg[1:0] spi_inhibit_refresh_buf;
	reg[1:0] spi_cmd_activate_buf;
	reg[1:0] spi_cmd_read_buf;
	
	reg spi_cmd_activate_ack;
	reg spi_cmd_read_ack;
	
	wire do_inhibit_refresh = (spi_inhibit_refresh_buf[1] || inhibit_refresh);
	
	wire[12:0] spi_row = spi_addr[21:9];
    wire[1:0] spi_bank = spi_addr[8:7];
    wire[8:0] spi_col = {spi_addr[6:0], 2'b0};

    wire[12:0] access_row = access_addr[23:11];
    wire[1:0] access_bank = access_addr[10:9];
    wire[8:0] access_col = access_addr[8:0];

	reg[3:0] readcount;
    reg[$clog2(BURST_LEN)-1:0] rdbuf_write_ptr;

    reg[$clog2(BURST_LEN)-1:0] wrbuf_read_ptr;

    integer i;

    always @(posedge clk)
    begin
        if (reset) begin
            state <= STA_INIT;
            cs_o <= 1;
            cmd_o <= CMD_NOP;
            ba_o <= 0;
            a_o <= 0;
            dq_oe_o <= 0;
            dq_o <= 0;
            dqm_o <= 2'b11;
            cke_o <= 1;

            cmd_busy <= 1;

            initcount <= 0;
            initrefreshcount <= 0;
            cmdcount <= 0;
            cmdtarget <= 0;
            refreshcount <= 0;
			
			read_buffer <= 0;
			read_busy <= 0;
			readcount <= 0;

			rdbuf_write_ptr <= 0;
            wrbuf_read_ptr <= 0;
			
			spi_inhibit_refresh_buf <= 0;
			spi_cmd_activate_buf <= 0;
			spi_cmd_read_buf <= 0;
			
			spi_cmd_activate_ack <= 0;
			spi_cmd_read_ack <= 0;
        end
        else begin
            refreshcount <= refreshcount + 1;
			
			spi_inhibit_refresh_buf <= {spi_inhibit_refresh_buf[0], spi_inhibit_refresh};
			spi_cmd_activate_buf <= {spi_cmd_activate_buf[0], spi_cmd_activate};
			spi_cmd_read_buf <= {spi_cmd_read_buf[0], spi_cmd_read};
			
			if (spi_cmd_activate_ack && (!spi_cmd_activate_buf[1])) spi_cmd_activate_ack <= 0;
			if (spi_cmd_read_ack && (!spi_cmd_read_buf[1])) spi_cmd_read_ack <= 0;

            // clear the busy flag one cycle before the true end of the current command
            // to allow for instant command chaining
            cmd_busy <= (state <= STA_INIT_REFRESH) ||
                        ((state != STA_IDLE) && (cmdcount < cmdtarget-1)) ||
                        (access_cmd != 2'b00) ||
                        ((refreshcount >= tREFRESH-1) && (!do_inhibit_refresh));

            if (state == STA_INIT) begin
                // wait for the SDRAM to start up (100us)

                if (initcount >= tINIT) begin
                    state <= STA_INIT_PRECHARGE;
                    cmdcount <= 1;
                    cmdtarget <= tRP;

                    cs_o <= 0;
                    cmd_o <= CMD_PRECHARGE;
                    dqm_o <= 2'b11;
                    a_o[10] <= 1; // all banks
                end
                else begin
                    initcount <= initcount + 1;
                    cmd_o <= CMD_NOP;
                end
            end
            else if ((state != STA_IDLE) && (cmdcount < cmdtarget)) begin
                // waiting for a command to finish

                if (state == STA_WRITE) begin
                    if (cmdcount < BURST_LEN) begin
                        // if doing a write, feed the input data

                        dq_oe_o <= 1;
                        dq_o <= write_buffer[wrbuf_read_ptr*16+:16];
                        dqm_o <= write_mask[wrbuf_read_ptr*2+:2];

                        wrbuf_read_ptr <= wrbuf_read_ptr + 1;
                    end
                    else begin
                        // write finished

                        dq_oe_o <= 0;
                        dqm_o <= 2'b11;
                    end
                end

                cmdcount <= cmdcount + 1;
                cmd_o <= CMD_NOP;
            end
            else begin
                // no command running, figure out what the next command will be
                cmdcount <= 1;

                if (state == STA_INIT_PRECHARGE) begin
                    state <= STA_INIT_REFRESH;
                    cmdtarget <= tRC;
                    initrefreshcount <= 0;

                    cs_o <= 0;
                    cmd_o <= CMD_REFRESH;
                end
                else if (state == STA_INIT_REFRESH) begin
                    if (initrefreshcount == 1) begin
                        state <= STA_SETMODE;
                        cmdtarget <= tMRD;
                        refreshcount <= 1;

                        cs_o <= 0;
                        cmd_o <= CMD_SETMODE;
                        dqm_o <= 2'b11;
                        ba_o <= 2'b00;          // reserved
                        a_o[12:10] <= 3'b000;   // reserved
                        a_o[9] <= 1'b0;         // write burst: enabled
                        a_o[8:7] <= 2'b00;      // operating mode
                        a_o[6:4] <= tCAS;       // CAS latency
                        a_o[3] <= 1'b0;         // burst type: sequential
                        a_o[2:0] <= BURST_MODE; // burst length
                    end
                    else begin
                        initrefreshcount <= 1;

                        cs_o <= 0;
                        cmd_o <= CMD_REFRESH;
                        dqm_o <= 2'b11;
                    end
                end
				else if (spi_cmd_activate_buf[1] && (!spi_cmd_activate_ack)) begin
					// activate row
                    state <= STA_ACTIVATE;
                    //cmd_busy <= 1;
                    cmdtarget <= tRCD;
					spi_cmd_activate_ack <= 1;

                    cs_o <= 0;
                    cmd_o <= CMD_ACTIVATE;
                    dqm_o <= 2'b11;
                    ba_o <= spi_bank;
                    a_o <= spi_row;
				end
				else if (spi_cmd_read_buf[1] && (!spi_cmd_read_ack)) begin
                    // read
                    state <= STA_READ;
                    //cmd_busy <= 1;
                    cmdtarget <= tREAD;
					read_busy <= 1;
					spi_cmd_read_ack <= 1;

                    cs_o <= 0;
                    cmd_o <= CMD_READ;
                    ba_o <= spi_bank;
                    a_o[8:0] <= spi_col;
                    a_o[10] <= 1; // auto precharge
                    dq_oe_o <= 0;
                    dqm_o <= 2'b00;
                end
                else if (access_cmd == 2'b11) begin
                    // activate row
                    state <= STA_ACTIVATE;
                    //cmd_busy <= 1;
                    cmdtarget <= tRCD;

                    cs_o <= 0;
                    cmd_o <= CMD_ACTIVATE;
                    dqm_o <= 2'b11;
                    ba_o <= access_bank;
                    a_o <= access_row;
                end
                else if (access_cmd == 2'b01) begin
                    // read
                    state <= STA_READ;
                    //cmd_busy <= 1;
                    cmdtarget <= tREAD;
					read_busy <= 1;

                    cs_o <= 0;
                    cmd_o <= CMD_READ;
                    ba_o <= access_bank;
                    a_o[8:0] <= access_col;
                    a_o[10] <= 1; // auto precharge
                    dq_oe_o <= 0;
                    dqm_o <= 2'b00;
                end
                else if (access_cmd == 2'b10) begin
                    // write
                    state <= STA_WRITE;
                    //cmd_busy <= 1;
                    cmdtarget <= tWRITE;
                    wrbuf_read_ptr <= 1;

                    cs_o <= 0;
                    cmd_o <= CMD_WRITE;
                    ba_o <= access_bank;
                    a_o[8:0] <= access_col;
                    a_o[10] <= 1; // auto precharge
                    dq_oe_o <= 1;
                    dq_o <= write_buffer[15:0];
                    dqm_o <= write_mask[1:0];
                end
                else if ((refreshcount >= tREFRESH) && (!do_inhibit_refresh)) begin
                    // if we are past due, send a refresh command
                    state <= STA_REFRESH;
                    //cmd_busy <= 1;
                    cmdtarget <= tRC;
                    refreshcount <= 1;

                    cs_o <= 0;
                    cmd_o <= CMD_REFRESH;
                    dqm_o <= 2'b11;
                end
                else begin
                    state <= STA_IDLE;
                    //cmd_busy <= 0;
                    cs_o <= 1;
                    cmd_o <= CMD_NOP;
                    dqm_o <= 2'b11;
                end
            end
			
			// if reading data, advance the read
			if ((readcount > tCAS) && (readcount <= tCAS+BURST_LEN)) begin
				read_buffer[rdbuf_write_ptr*16+:16] <= dq_i;
				if (rdbuf_write_ptr == BURST_LEN-1) read_busy <= 0;
                rdbuf_write_ptr <= rdbuf_write_ptr + 1;
			end
			else
				rdbuf_write_ptr <= 0;
			
			readcount <= (state == STA_READ) ? cmdcount : 0;
        end
    end

endmodule
