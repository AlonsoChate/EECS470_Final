
`timescale 1ns/100ps

module memtb;


    `define CACHE_MODE
    logic clk;
    logic [`XLEN-1:0] proc2mem_addr;
    logic [3:0] mem2proc_tag, mem2proc_response;
    BUS_COMMAND proc2mem_command;
    logic [63:0] proc2mem_data, mem2proc_data;
	MEM_SIZE proc2mem_size;

    mem memory(.*); // connected to the above signals

   // Generate System Clock
	always begin
		#(`VERILOG_CLOCK_PERIOD/2.0);
		clk = ~clk;
	end

    // Show contents of a range of Unified Memory, in both hex and decimal
	task show_mem_with_decimal;
		input [31:0] start_addr;
		input [31:0] end_addr;
		int showing_data;
		begin
			$display("@@@");
			showing_data=0;
			for(int k=start_addr;k<=end_addr; k=k+1)
				if (memory.unified_memory[k] != 0) begin
					$display("@@@ mem[%5d] = %x : %0d", k*8, memory.unified_memory[k], 
				                                            memory.unified_memory[k]);
					showing_data=1;
				end else if(showing_data!=0) begin
					$display("@@@");
					showing_data=0;
				end
			$display("@@@");
		end
	endtask  // task show_mem_with_decimal

	logic [`XLEN-1:0] temp;

	semaphore mem_busy;

	// Non-blocking task to send store to memory
	task automatic write_memory(input logic[`XLEN-1:0] addr, input logic[63:0] data, input MEM_SIZE size);
		logic [3:0] tag;
		fork 
		begin		
			tag = 4'b0;
			mem_busy.get(1); // acquire lock on memory bus
			while(tag == 0) begin // keep trying until we get a non-zero (valid) tag
				proc2mem_addr = addr; // store's address
				proc2mem_command = BUS_STORE; // store command
				proc2mem_data = data; // data input
				proc2mem_size = size; // size parameter (WORD or DOUBLE)
				@(posedge clk); // wait until next posedge to check signal
				tag = mem2proc_response; // save response as tag
			end

			proc2mem_command = BUS_NONE; // turn off command when done
			mem_busy.put(1); // unlock memory bus
			
			// "Wait" for transaction to return (writes do not have to wait as they are instantly observable
			$display("\n@@ %2d:ST of size %6s to address:%8h=%8h at t=%0d", tag, size.name(), addr, data, $time);
		end 
		join_none
	endtask

	// Non-blocking task to send load to memory
	task automatic read_memory(input logic[`XLEN-1:0] addr, output logic[63:0] data, input MEM_SIZE size);
		logic [3:0] tag;
		fork 
		begin
			tag = 4'b0;
			mem_busy.get(1); // acquire lock on memory bus
			while(tag == 0) begin // keep trying until we get a non-zero (valid) tag
				proc2mem_addr = addr; // load's address
				proc2mem_command = BUS_LOAD; // load command
				proc2mem_size = size; // size parameter
				@(posedge clk); // wait until next posedge to check signal
				tag = mem2proc_response; // save response as tag
			end
			proc2mem_command = BUS_NONE; // turn off command when done
			mem_busy.put(1); // unlock memory bus
			
			// Wait for transaction to return
			$display("\n@@ %2d:RD of size %6s to address:%8h at time=%0d", tag, size.name(), addr, $time);
			@(negedge clk);
			while(tag != mem2proc_tag) begin // transaction finishes when mem tag matches this transaction's tag
				@(posedge clk);
			end
			data = mem2proc_data; // save the data
			$display("\n@@ %2d:Loaded 0x%08h=%8h at time=%0d", tag, addr, mem2proc_data, $time);
		end 
		join_none
	endtask

	task automatic nclk(input int n);
		while( n-- > 0) begin
			@(negedge clk);
		end
	endtask

	task automatic pclk(input int n);
		while( n-- > 0) begin
			@(posedge clk);
		end
	endtask

// `define VERBOSE
// Define VERBOSE to see the signals and memory live

    initial begin 
        clk = 0;
        proc2mem_command = BUS_NONE;
		mem_busy = new(1);
        $display("STARTING MEM TESTBENCH(DELAY=%0d CYCLES)", `MEM_LATENCY_IN_CYCLES);

		`ifdef VERBOSE
		$monitor("proc2mem_command:%09s|proc2mem_addr:%08h|mem2proc_response:%02d|mem2proc_tag:%02d", 
			proc2mem_command.name(), proc2mem_addr, mem2proc_response, mem2proc_tag);
		`endif

		/*
		Explanation:
		read_memory and write_memory are non-blocking tasks that will read and write to memory respectively.
		Because they are non-blocking, you must "wait" a sufficient period of time for their outputs to be 
		visible. While the functions are non-blocking they are still synchronized such that only one request
		ever is sent to the memory controller per clock cycle and they are determinisitc as the order seen
		below reflect the total order of the underlying requests. (Verilog lock scheduling is simply FIFO).


		Output format:
		Each request will print a string when it is able to communicate with the memory controller. The number
		at the start of the string is the tag recieved from the controller.

		Loads will eventually print a message when the controller gives the tag and data for the request.


		*/

		read_memory(32, temp, WORD);
		read_memory(48, temp, WORD);
		write_memory(48, 98, WORD);
		@(posedge clk); // gap cycle
		read_memory(64, temp, WORD);
		read_memory(48, temp, WORD);
		write_memory(80, 128, DOUBLE);
		read_memory(80, temp, WORD);
		// feel free to add more
		
		pclk(1000); // drain the request queue

		`ifdef VERBOSE
		show_mem_with_decimal(0, `MEM_SIZE_IN_BYTES);
		`endif

        $finish;
    end

endmodule