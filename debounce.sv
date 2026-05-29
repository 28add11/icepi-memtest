module debouncer #(
	parameter n = 20
	)(
	input clk,
	input bouncy_sig,
	output reg sig
	);

	reg [n-1:0] counter;

	always_ff @(posedge clk) begin
		if (bouncy_sig != sig) begin
			counter <= counter + 1;
			if (counter == (2**n - 1)) begin
				sig <= bouncy_sig;
			end
		end else begin
			counter <= 0;
		end
	end
	
endmodule