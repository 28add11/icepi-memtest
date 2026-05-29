module top #(
	parameter ignore = 1
	) (
	input wire clk,
	
	output logic [4:0] led,
	input logic [1:0] button,

	output [12:0] sdram_a,
	inout [15:0] sdram_dq,
	output [1:0] sdram_ba,
	output [1:0] sdram_dqm,

	output sdram_wen,
	output sdram_casn,
	output sdram_rasn,

	output sdram_csn,
	output sdram_cke,
	output sdram_clk
	);
	
	// Block adapted from https://github.com/cheyao/icepi-zero/blob/main/firmware/sdram/memtest/ecp5pll.sv 
	wire [3:0] sys_sdram_clocks;
    wire sys_sdram_clocks_locked;
    ecp5pll #(
          .in_hz( 50*1000000),
        .out0_hz(123.15*1000000), .out0_tol_hz(500000),// Max IO pin speed :(
        .out1_hz(123.15*1000000), .out1_tol_hz(500000), .out1_deg(75), // 75 degrees is ballpark for most margin w/ tAC and all that jazz
        .out2_hz( 25*1000000), .out2_tol_hz(1*1000000), // not used
        .out3_hz( 25*1000000), .out3_tol_hz(1*1000000)  // not used
    ) clk_sdram_sys_inst (
        .clk_i(clk),
        .clk_o(sys_sdram_clocks),
        .locked(sys_sdram_clocks_locked)
    );
    wire clock = sys_sdram_clocks[0];
	assign sdram_clk = sys_sdram_clocks[1];

	// Reset logic
	wire rst_n;

	debouncer rstDebounce(
		.clk(clock),
		.bouncy_sig(button[1] & sys_sdram_clocks_locked), // Active low reset, if one is low we reset
		.sig(rst_n)
	);

	// Control logic and the actual SRAM module
	wire [23:0] testAddr = testCount[23:0];
	wire [15:0] testData;
	reg [15:0] expectedTestData;
	wire [15:0] testDataReturned;
	wire [1:0] dqm = 0;
	
	reg [1:0] state;
	wire startTransaction;
	reg testGood;
	reg [29:0] testCount;

	assign led[0] = testGood;
	assign led[4:1] = testCount[23:20];

	wire sramReady;
	wire sramValid;

	sramInterface sram (
		.clk(clock),
		.rst_n(rst_n),

		.sd_address(sdram_a),
		.sd_bank(sdram_ba),
		.sd_data_inout(sdram_dq),
		.sd_chipSel(sdram_csn),
		.sd_ras(sdram_rasn),
		.sd_cas(sdram_casn),
		.sd_we(sdram_wen),
		.sd_dqm(sdram_dqm),
		.sd_cke(sdram_cke),

		.din(testData),
		.dout(testDataReturned),
		.addr(testAddr),
		.dqm(dqm),
		.rw(state[1]),
		.transaction(startTransaction),

		.ready(sramReady),
		.valid(sramValid)
	);

	assign startTransaction = sramReady && ~state[0];

	reg [31:0] randGen;
	assign testData = randGen[31:16];

	always_ff @(posedge clock) begin
		if (~rst_n) begin
			testGood <= 1;
			state <= 0;
			testCount <= 0;
			randGen <= "hi:D";
		end else begin
			randGen <= {randGen[30:0], (randGen[31] ^ randGen[29] ^ randGen[25] ^ randGen[24])}; // PRNG

			case (state)
				2'b00: begin // Start write
					if (sramReady) begin
						state <= 2'b10;
						expectedTestData <= testData;
					end
				end

				2'b10: begin // Start read
					if (sramReady) state <= 2'b11;
				end

				2'b11: begin // Check that data is good
					if (sramValid) begin
						if (testDataReturned != expectedTestData) begin
							testGood <= 0;
						end

						state <= 0;
						testCount <= testCount + 1;
					end
				end
				default: state <= 2'b00;
			endcase
		end
	end

endmodule