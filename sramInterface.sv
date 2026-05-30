`default_nettype none

module sramInterface (
	input wire clk,
	input wire rst_n,
	
	// Pins going to the SDRAM chip
	output logic [12:0] sd_address,
	output logic [1:0] sd_bank,
	inout logic [15:0] sd_data_inout,
	output logic sd_chipSel,
	output logic sd_ras,
	output logic sd_cas,
	output logic sd_we,
	output logic [1:0] sd_dqm,
	output logic sd_cke,

	// Control logic from the processor/bus/whatever you hook this up to!
	input logic [15:0] din,
	output logic [15:0] dout,
	input logic [23:0] addr,
	input logic [1:0] dqm,
	input logic rw, // 1 for read, 0 for write
	input logic transaction, // assert for r/w transaction to start

	output logic ready, // Can perform a transaction
	output logic valid // Read data valid on dout
	);
	
	// Control params
	localparam MODE = 15'b000001000100000; // Single reads/writes, length 1, sequential addressing, CAS latency 2

	reg [3:0] cmd;
	assign sd_we = cmd[0];
	assign sd_cas = cmd[1];
	assign sd_ras = cmd[2];
	assign sd_chipSel = cmd[3];

	// Reset logic
	// Need to wait 200us before using memory (24630 cycles @ 123.15 MHz)
	reg [14:0] rstDelayCount; 

	wire sd_reset;
	assign sd_reset = |rstDelayCount;

	always_ff @(posedge clk) begin 
		if (~rst_n) begin
			rstDelayCount <= 24630 + 2 + 2 + 64; // 200us startup + 15ns precharge wait + 2cycles mode register set wait + 8 * 60ns refresh delay
		end else if (sd_reset) begin
			rstDelayCount <= rstDelayCount - 1;
		end
	end

	// commands (stolen from https://github.com/cheyao/icepi-zero/blob/main/firmware/sdram/memtest/sdram.v lol)
	localparam CMD_NOP             = 4'b0111;
	localparam CMD_ACTIVE          = 4'b0011;
	localparam CMD_READ            = 4'b0101;
	localparam CMD_WRITE           = 4'b0100;
	localparam CMD_BURST_TERMINATE = 4'b0110;
	localparam CMD_PRECHARGE       = 4'b0010;
	localparam CMD_AUTO_REFRESH    = 4'b0001;
	localparam CMD_LOAD_MODE       = 4'b0000;

	// Refresh timing registers
	// We send a refresh every ~7.8us
	// corresponds to about 962 cycles at our speed
	// 5% margin for safety gives ~914 cycles between refreshes
	reg [9:0] refreshTimer;
	wire refreshSoon;
	assign refreshSoon = (refreshTimer == 914);

	// In future should add logic to detect if we're in the same row and only precharge and bank activate if we're not

	// Control state machine
	localparam STATE_WAIT = 4'b0000;
	localparam STATE_OP = 4'b0101; // 5 cycles after banksel (sent on transition from wait to 1), corresponds to tRAS offset while complying w/ 15ns tRCD delay
	localparam STATE_DATABACK = 4'b1000; // CAS latency is 2 cycles, this is 2 cycles after command will be registered by ram. Doubles as end of refresh cycle
	localparam STATE_DONE = 4'b1010; // Since we are auto precharging, we can return to waiting after the tRP delay.

	reg [3:0] state; // Also use state as a timer

	assign ready = (state == STATE_WAIT) && (~refreshSoon) && ~sd_reset;
	assign valid = (state == (STATE_DATABACK + 1)) && rwReg;

	// Data we'll need later in the transaction
	reg trActive;
	reg rwReg;
	reg [23:0] fullAddr;
	reg [15:0] data;

	assign sd_data_inout = rwReg ? 16'hzzzz : data;
	assign dout = data;

	always_ff @(posedge clk) begin
		if (sd_reset) begin
			refreshTimer <= 0;
			state <= STATE_WAIT;

			sd_dqm <= 2'b11; // High during the initial pause as recommended by datasheet
			sd_cke <= 1; // We just keep it high, but in future I should probably support power down modes

			unique if (rstDelayCount > 68) begin // Initial delay
				cmd <= CMD_NOP;
			end else if (rstDelayCount == 68) begin
				cmd <= CMD_PRECHARGE;
				sd_address[10] <= 1; // All banks 
			end else if (rstDelayCount == 66) begin
				cmd <= CMD_LOAD_MODE;
				{sd_bank, sd_address} <= MODE;
			end else if (rstDelayCount[2:0] == 0 && rstDelayCount != 1) begin // Auto refresh, sending once every 8 cycles except on 0
				cmd <= CMD_AUTO_REFRESH;
			end else begin
				cmd <= 4'b1xxx;
			end

		end else begin

			if (~refreshSoon) begin
				refreshTimer <= refreshTimer + 1;
			end

			case (state)
				STATE_WAIT: begin
					if (refreshSoon) begin
						state <= state + 1;
						trActive <= 0;
						rwReg <= 0; // Works around issue in refreshes
						// If refreshSoon is asserted during a read, valid will never go high even when it's supposed to
						// instead we just clear rwReg here.
						cmd <= CMD_AUTO_REFRESH;

					end else if (transaction) begin // Send bank select
						state <= state + 1;
						trActive <= 1;
						rwReg <= rw;
						fullAddr <= addr;
						data <= din; // Doesn't matter if din is invalid for read, we just rewrite it later

						sd_bank <= addr[10:9]; // Interleave banks for future's sake (can have large contiguous open addresses)
						sd_address <= addr[23:11];
						sd_dqm <= dqm;
						cmd <= CMD_ACTIVE;
					end
				end

				STATE_OP: begin // Send read or write command
					state <= state + 1; // Keep incrumenting regardless for the refresh

					if (trActive) begin
						// Leave sd_bank unchanged since it's already at the value we want
						sd_address[10] <= 1; // Auto precharge
						sd_address[8:0] <= fullAddr[8:0];

						cmd <= rwReg ? CMD_READ : CMD_WRITE;
					end
				end

				STATE_DATABACK: begin // Get read data
					if (trActive) begin 
						state <= state + 1;
						if (rwReg) begin // Get the actual data back
							data <= sd_data_inout;
						end
						
					end else if (refreshSoon) begin// End of refresh state
						refreshTimer <= 0;
						state <= STATE_WAIT;
					end
				end

				STATE_DONE: begin
					state <= STATE_WAIT;
				end

				default: begin
					state <= state + 1;
					cmd <= 4'b1xxx;
				end
			endcase
		end
	end

endmodule
