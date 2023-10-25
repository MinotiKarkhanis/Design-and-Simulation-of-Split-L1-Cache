`define EOF 32'hFFFF_FFFF
`define NULL 0
module L1_split_cache();

// General parameters

parameter SETS = 16384;
parameter WAYS_IC = 4;
parameter WAYS_DC = 8;
parameter TAG_WIDTH = 12;
parameter INDEX_WIDTH = 14;
parameter BYTESEL_WIDTH = 6;
parameter ADDRESS_WIDTH = 32;
parameter MODE = 0;



// MESI parameters

parameter
  Invalid   = 2'b00,
  Modified  = 2'b01,
  Exclusive = 2'b10,
  Shared    = 2'b11;
  
// File I/O parameters

integer file;
real hit_ratio;
integer r;
integer N;
integer total_operations = 0;
real cache_references = 0.0;
integer cache_reads = 0;
integer cache_miss = 0;
integer cache_writes = 0;
reg [ADDRESS_WIDTH-1:0] Address;
reg [TAG_WIDTH-1:0] Tag;
reg [INDEX_WIDTH-1:0] Index;
reg [BYTESEL_WIDTH-1:0] ByteSel;

// Three dimensional arrays for storing data 

reg Valid_IC[0:SETS-1][0:WAYS_IC-1];
reg Valid_DC[0:SETS-1][0:WAYS_DC-1];
reg [11:0] StoredTag_DC[0:SETS-1][0:WAYS_DC-1];
reg [11:0] StoredTag_IC[0:SETS-1][0:WAYS_IC-1];
reg [13:0] Index_DC[0:SETS-1][0:WAYS_DC-1];
reg [13:0] Index_IC[0:SETS-1][0:WAYS_IC-1];
reg [1:0] LRUbits_IC[0:SETS-1][0:WAYS_IC-1];
reg [2:0] LRUbits_DC[0:SETS-1][0:WAYS_DC-1];
reg [1:0] StoredMESI_IC[0:SETS-1][0:WAYS_IC-1];
reg [1:0] StoredMESI_DC[0:SETS-1][0:WAYS_DC-1];
reg StoredHit_IC[0:SETS-1][0:WAYS_IC-1];
reg StoredHit_DC[0:SETS-1][0:WAYS_DC-1];
reg [1:0] StoredC_DC[0:SETS-1][0:WAYS_DC-1];
reg [1:0] StoredC_IC[0:SETS-1][0:WAYS_IC-1];
reg [ADDRESS_WIDTH-1:0] TempAddress;
reg DONE;


// Integers for "for" loops

integer i;
integer j;

// HitCount is a real, so the ratio can be calculated correctly
real HitCount;


initial
begin : file_block
	file = $fopen("./trace.txt","r");
   
	
	// Set initial values
    initialize();
	HitCount = 0.0;
        
    if (file == `NULL)
        disable file_block;

        while ( ! $feof(file))
		begin
		
        N = $fgetc(file);
		N = N - 48;
		
        case (N)
        0:  // read data request to L1 data cache 
            begin
				r = $fscanf(file," %h:\n", Address);
				Tag = Address[31:20];
				Index = Address[19:6];
				ByteSel = Address[5:0];
				total_operations = total_operations +1;
				cache_references = cache_references +1.0;
				cache_reads = cache_reads +1;
				
				set(N, Tag, Index, ByteSel);
				
            end
			
        1: // write data request to L1 data cache 
            begin
				r = $fscanf(file," %h:\n", Address);
				Tag = Address[31:20];
				Index = Address[19:6];
				ByteSel = Address[5:0];
				total_operations = total_operations+1;
				cache_references = cache_references+1.0;
				cache_writes = cache_writes+1;
				
				set(N, Tag, Index, ByteSel);
				
            end
			
        2: // Instruction fetch (a read request to L1 instruction cache) 
            begin
				r = $fscanf(file," %h:\n", Address);
				Tag = Address[31:20];
				Index = Address[19:6];
				ByteSel = Address[5:0];
				total_operations = total_operations+1;
				cache_references = cache_references+1.0;
				cache_reads = cache_reads+1;
				
				set(N, Tag, Index, ByteSel);
            end
			
        3: // Invalidate command from L2 
            begin
				r = $fscanf(file," %h:\n", Address);
				Tag = Address[31:20];
				Index = Address[19:6];
				ByteSel = Address[5:0];
				total_operations = total_operations+1;
				cache_references = cache_references+1.0;
				
				set(N, Tag, Index, ByteSel);
            end
			
        4: // Data request from L2 (in response to snoop)
            begin
				r = $fscanf(file," %h:\n", Address);
				Tag = Address[31:20];
				Index = Address[19:6];
				ByteSel = Address[5:0];
				total_operations = total_operations+1;
				cache_references = cache_references+1.0;
				
				set(N, Tag, Index, ByteSel);
            end

        8: // Clear cache and reset all states and statistics 
			begin
				initialize();
				cache_references = 0;
				total_operations = 0;
				cache_reads=0;
				cache_writes=0;
				HitCount=0;
				cache_miss=0;
			end
			
        9:  // Print contents and states of the cache (allow subsequent trace activity)
			begin
				write_out();
				total_operations = total_operations+1;
            end
			
        default:
            $display("");
            
        
        endcase
		
        end 

        $display("Total number of cache reads:  %d \n", cache_reads);
        $display("Total number of cache writes: %d \n", cache_writes);
        $display("Total number of cache hits:    %d \n", HitCount);
        $display("Total number of cache miss :  %d \n", cache_miss); 
		    
        if (cache_references != 0)
			hit_ratio = HitCount/(HitCount+cache_miss);
		else
			hit_ratio = 0.0;
        
        $display("Hit ratio:  %f \n", hit_ratio);
        
        
    
    $fclose(file);
end 

task set;
	input [3:0]N;
	input [TAG_WIDTH-1:0]Tag;
	input [INDEX_WIDTH-1:0]Index;
	input [BYTESEL_WIDTH-1:0]ByteSel;
	
	begin
		case (N)
		  // Read data request from L1 data cache 
		  0: begin
			// Clear stored hit values
			for (i = 0; i < WAYS_DC; i = i+1)
			  begin
				StoredHit_DC[Index][i] = 0;
			  end
			for (i = 0; i < WAYS_DC; i = i + 1)
			  begin
				if (DONE == 0)    // Continue if the right line hasn't been found
				  begin
					if (Valid_DC[Index][i] == 1)    // Something exists in this line
					  begin
						if (StoredTag_DC[Index][i] == Tag)    // Correct tag found
						  begin
							if (StoredMESI_DC[Index][i] == 2'b00)   // Cache line is Invalid
							  begin
								StoredHit_DC[Index][i] = 0;   // Coherence MISS
								StoredC_DC[Index][i] = 2'b11;
								// Report MISS to monitor
								cache_miss = cache_miss + 1;
								TempAddress = {Tag, Index, ByteSel};
								if(MODE==1)
                                                                $display(" Read from L2 from Address %h",TempAddress);
								StoredMESI_DC[Index][i] = 2'b10;
								// Adjust LRU bits
								LRUreplacement_DC();
								DONE = 1;
							  end
							else  if (StoredMESI_DC[Index][i] == 2'b01) // HIT
							  begin
								StoredHit_DC[Index][i] = 1;
								// Report HIT to monitor
								HitCount = HitCount + 1.0;
								StoredMESI_DC[Index][i] = 2'b01;
								// Adjust LRU bits
								LRUreplacement_DC();
								DONE = 1;
							  end
							else  if (StoredMESI_DC[Index][i] == 2'b10) // HIT
							  begin
								StoredHit_DC[Index][i] = 1;
								// Report HIT to monitor
								HitCount = HitCount + 1.0;
								StoredMESI_DC[Index][i] = 2'b11;
								// Adjust LRU bits
								LRUreplacement_DC();
								DONE = 1;
							  end
						     else  if (StoredMESI_DC[Index][i] == 2'b11) // HIT
							  begin
								StoredHit_DC[Index][i] = 1;
								// Report HIT to monitor
								HitCount = HitCount + 1.0;
								StoredMESI_DC[Index][i] = 2'b11;
								// Adjust LRU bits
								LRUreplacement_DC();
								DONE = 1;
							  end
						  end
						//else Conflict MISS - continue to the next line
					  end
					else    // Compulsory MISS
					  begin
						StoredHit_DC[Index][i] = 0;
						StoredC_DC[Index][i] = 2'b00;
						// Report MISS to monitor
						cache_miss = cache_miss + 1;
						TempAddress = {Tag, Index, ByteSel};
						// Write StoredTag bits
						StoredTag_DC[Index][i] = Tag;
						// send Data request for L2 cache 
						if(MODE==1)
						$display(" Read from L2 from Address %h",TempAddress);					
						StoredMESI_DC[Index][i] = 2'b10;
						// Adjust LRU bits
						LRUreplacement_DC();
						Valid_DC[Index][i] = 1;
						DONE = 1;
					  end
				  end
			  end
			// End of FOR loop signifies Capacity MISS (something needs to be evicted)
			if (DONE == 0)    // Continue if the right line hasn't been found
			  begin
				// Report MISS to monitor
				cache_miss = cache_miss + 1;
				for (i = 0; i < WAYS_DC; i = i + 1)
				  begin
					if (DONE == 0)
					  begin
						if (LRUbits_DC[Index][i] == 7)    // Find least recently used line
						  begin
							StoredHit_DC[Index][i] = 0;
							TempAddress = {Tag, Index, ByteSel};
							if (StoredMESI_DC[Index][i] == 2'b01 || StoredMESI_DC[Index][i] == 2'b10 || StoredMESI_DC[Index][i] == 2'b11 )    // If the line is modified, write back to memory
							  begin
							   // Report write-back to L2 cache
							   if (MODE==1) 
                                                           $display("Write back to L2 cache");
							   StoredMESI_DC[Index][i] = 2'b01;
							  
							// Overwrite StoredTag
							StoredTag_DC[Index][i] = Tag;
							// send Data request for L2 cache 
							if(MODE==1)
                                                        $display("Read from L2 from Address %h",TempAddress);
							LRUreplacement_DC();
							Valid_DC[Index][i] = 1;
							DONE = 1;
							end
						  end
					  end
				  end
			  end
			// After the line has been read (one way or another) reset DONE to 0
		DONE = 0;		
		  end
// Write data request to L1 data cache
		  1: begin
			// Clear stored hit values
			for (i = 0; i < WAYS_DC; i = i+1)
			  begin
				StoredHit_DC[Index][i] = 0;
			  end
			for (i = 0; i < WAYS_DC; i = i + 1)
			  begin
				if (DONE == 0)
				  begin
					if (Valid_DC[Index][i] == 1)    // Something exists in this line
					  begin
						if (StoredTag_DC[Index][i] == Tag)    // Correct tag found
						  begin
							if (StoredMESI_DC[Index][i] == 2'b00)   // Cache line is Invalid
							  begin
								StoredHit_DC[Index][i] = 0;// Coherence MISS
								cache_miss = cache_miss + 1;
								TempAddress = {Tag, Index, ByteSel};
								if(MODE==1)
                                                                $display("Read data from L2 cache from %h address",TempAddress);
								StoredMESI_DC[Index][i] = 2'b01;
								// Adjust LRU bits
								LRUreplacement_DC();
								// Report full cache line to monitor
								DONE = 1;
							  end
							else if (StoredMESI_DC[Index][i] == 2'b01)  // HIT to Modified line
							  begin
								StoredHit_DC[Index][i] = 1;
								TempAddress = {Tag, Index, ByteSel};
								// Report HIT to monitor
								HitCount = HitCount + 1.0;
								StoredMESI_DC[Index][i] = 2'b01;
								LRUreplacement_DC();
								DONE = 1;
							  end

							else if (StoredMESI_DC[Index][i] == 2'b10)  // HIT to Exclusive line
							  begin
								StoredHit_DC[Index][i] = 1;
								TempAddress = {Tag, Index, ByteSel};
								// Report HIT to monitor
								HitCount = HitCount + 1.0;
								StoredMESI_DC[Index][i] = 2'b01;
								LRUreplacement_DC();
								DONE = 1;
							  end

							else if (StoredMESI_DC[Index][i] == 2'b11)  // HIT to Shared line
							  begin
								StoredHit_DC[Index][i] = 1;
								TempAddress = {Tag, Index, ByteSel};
								// Report HIT to monitor
								HitCount = HitCount + 1.0;
								StoredMESI_DC[Index][i] = 2'b01;
								// Adjust LRU bits
								LRUreplacement_DC();
								DONE = 1;
							  end
							
						  end
						//else Conflict MISS - continue to the next line
					  end
					else    // Compulsory MISS
					  begin
						// report miss to monitor
						cache_miss = cache_miss + 1;
						TempAddress = {Tag, Index, ByteSel};
			                       if(MODE==1)
                                                $display(" Write through to L2 %h",TempAddress);
						// Write StoredTag bits
						StoredTag_DC[Index][i] = Tag;
						StoredMESI_DC[Index][i] = 2'b01;
						// Adjust LRU bits
						LRUreplacement_DC();
						Valid_DC[Index][i] = 1;
						// Report full cache line to monitor
						DONE = 1;
					  end
				  end
			  end
			
			// End of FOR loop signifies Capacity MISS (something needs to be evicted)
			if (DONE == 0)    // Continue if the right line hasn't been found
			  begin
				// Report MISS to monitor
					cache_miss = cache_miss + 1;
				for (i = 0; i < WAYS_DC; i = i + 1)
				  begin
					if (DONE == 0)
					  begin
						if (LRUbits_DC[Index][i] == 7)    // Find least recently used line
						  begin
							StoredHit_DC[Index][i] = 0;
							TempAddress = {StoredTag_DC[Index][i], Index, ByteSel};
							if (StoredMESI_DC[Index][i] == 2'b01)
							  begin
							   if(MODE==1)
							    $display(" Write-back to L2");
							StoredTag_DC[Index][i] = Tag;
							// Regardless, pull from memory and overwrite the evicted line
							TempAddress = {Tag, Index, ByteSel};
							StoredMESI_DC[Index][i] = 2'b01;
							// Adjust LRU bits
							LRUreplacement_DC();
							Valid_DC[Index][i] = 1;
							// Report full cache line to monitor
							DONE = 1;
						         end
							else if (StoredMESI_DC[Index][i] == 2'b10)
							  begin								
							StoredTag_DC[Index][i] = Tag;
							// Regardless, pull from memory and overwrite the evicted line
							TempAddress = {Tag, Index, ByteSel};
						  	StoredMESI_DC[Index][i] = 2'b01;
							// Adjust LRU bits
							LRUreplacement_DC();
							Valid_DC[Index][i] = 1;
							// Report full cache line to monitor
							DONE = 1;
						  end
						else if (StoredMESI_DC[Index][i] == 2'b11)
							  begin 
							// Overwrite StoredTag bits
							StoredTag_DC[Index][i] = Tag;
							// Regardless, pull from memory and overwrite the evicted line
							TempAddress = {Tag, Index, ByteSel};
							StoredMESI_DC[Index][i] = 2'b01;
							// Adjust LRU bits
							LRUreplacement_DC();
							Valid_DC[Index][i] = 1;
							// Report full cache line to monitor
							DONE = 1;
						  end



					  end
				  end
			  end
end
			// After the line has been read (one way or another) reset DONE to 0
			DONE = 0;
		  end
		  
//Instruction fetch (a read request to L1 instruction cache)
 2: begin
			// Clear stored hit values
			for (i = 0; i < WAYS_IC; i = i+1)
			  begin
				StoredHit_IC[Index][i] = 0;
			  end
			for (i = 0; i < WAYS_IC; i = i + 1)
			  begin
				if (DONE == 0)    // Continue if the right line hasn't been found
				  begin
					if (Valid_IC[Index][i] == 1)    // Something exists in this line
					  begin
						if (StoredTag_IC[Index][i] == Tag)    // Correct tag found
						  begin
							if (StoredMESI_IC[Index][i] == 2'b00)   // Cache line is Invalid
							  begin
								StoredHit_IC[Index][i] = 0;   // Coherence MISS
								StoredC_IC[Index][i] = 2'b11;
								// Report MISS to monitor
					            cache_miss = cache_miss + 1;
								TempAddress = {Tag, Index, ByteSel};
							if(MODE==1)
      							$display("Read from L2 %h",TempAddress);	
								// Adjust MESI bits
								mesi_IC(N);
								// Adjust LRU bits
								LRUreplacement_IC();
								DONE = 1;
							  end
							else if (StoredMESI_IC[Index][i] == 2'b01)  // HIT and in Modified State
							  begin
								StoredHit_IC[Index][i] = 1'b1;
								StoredC_IC[Index][i] = 2'b00;

								// Report HIT to monitor
								HitCount = HitCount + 1.0;	 
								// Adjust LRU bits
								LRUreplacement_IC();
								mesi_IC(N);
								DONE = 1;
							  end
    							else if (StoredMESI_IC[Index][i] == 2'b10)  // HIT and in Exclusive State)
							  begin
								StoredHit_IC[Index][i] = 1;
								StoredC_IC[Index][i] = 2'b00;

								// Report HIT to monitor
								HitCount = HitCount + 1.0; 
								// Adjust LRU bits
								LRUreplacement_IC();
								mesi_IC(N);
								DONE = 1;
							  end
							else if (StoredMESI_IC[Index][i] == 2'b11)  // HIT and in Shared State)
							  begin
								StoredHit_IC[Index][i] = 1;
								StoredC_IC[Index][i] = 2'b00;

								// Report HIT to monitor
								HitCount = HitCount + 1.0; 
								// Adjust LRU bits
								LRUreplacement_IC();
								mesi_IC(N);
								DONE = 1;
							  end
						  end
						//else Conflict MISS - continue to the next line
					  end
					else    // Compulsory MISS
					  begin
						StoredMESI_IC[Index][i] = 2'b10;
						StoredHit_IC[Index][i] =1'b0;
						//StoredC_IC[Index][i] = 2'b00;
						TempAddress = {Tag, Index, ByteSel};
						if(MODE==1)
						$display("Read from L2 %h",TempAddress);
						// Report MISS to monitor
						cache_miss = cache_miss + 1;
						// Write StoredTag bits
						StoredTag_IC[Index][i] = Tag;	 	
						// Adjust LRU bits
						LRUreplacement_IC();
						Valid_IC[Index][i] = 1;
						DONE = 1;
					  end
				  end
			  end
			// End of FOR loop signifies Capacity MISS (something needs to be evicted)
			if (DONE == 0)    // Continue if the right line hasn't been found
			  begin
				// Report MISS to monitor
				cache_miss = cache_miss + 1;
				for (i = 0; i < WAYS_IC; i = i + 1)
				  begin
					if (DONE == 0)
					  begin
						if (LRUbits_IC[Index][i] == 3)    // Find least recently used line
						  begin
							StoredHit_IC[Index][i] = 0;
							//StoredC_IC[Index][i] = 2'b10;
							TempAddress = {Tag, Index, ByteSel};
							if (StoredMESI_IC[Index][i] == 2'b01 || StoredMESI_DC[Index][i] == 2'b10 || StoredMESI_DC[Index][i] == 2'b11)    // If the line is modified, write back to memory
							  begin
								// Report write-back to L2 cache
								if(MODE==1)
								$display("Write back to L2 cache");
							  end
							// Overwrite StoredTag
							StoredTag_IC[Index][i] = Tag;
							// send Data request for L2 cache 
			                                if (MODE==1)
                                                        $display("Read from L2 cache %h",TempAddress);
							//$display("Write to L2 %h",TempAddress);
							// Adjust LRU bits
							LRUreplacement_IC();
							Valid_IC[Index][i] = 1;
							DONE = 1;
						  end
					  end
				  end
			  end
			// After the line has been read (one way or another) reset DONE to 0
			DONE = 0;		
		  end

//Invalidate command from L2
3: begin
		  // Checking in Data Cache  
			// Clear stored hit values
			for (i = 0; i < WAYS_DC; i = i + 1)
			  begin
				StoredHit_DC[Index][i] = 0;
			  end
			for (i = 0; i < WAYS_DC; i = i + 1)
			  begin
				if (DONE == 0)    // Line has not been found
				  begin
					if (Valid_DC[Index][i] == 1)    // Something exists in this line
					  begin
						if (StoredTag_DC[Index][i] == Tag)    // Check Tags
						  begin
							StoredHit_DC[Index][i] = 1;
							// Report HIT to monitor
							//HitCount = HitCount + 1.0;
							TempAddress = {Tag, Index, ByteSel};
							if (StoredMESI_DC[Index][i] == 2'b11)   // If line is in Shared state and it is modified by the other processor
							  begin
								// Report write-back to L2 cache
								if (MODE==1)
								$display("Write back to L2 cache");
								//L2_cache(N, TempAddress);
							  end
							 // set valid bit zero
							 Valid_IC[Index][i] = 0;
							// MESI bits set
							mesi_DC(N);
							// Adjust LRU bits
							LRUreplacement_DC();
							DONE = 1;
						  end
					  end
				  end
			  end
			// End of FOR loop signifies Capacity MISS (we don't have the line)
			// Only run this code if the line hasn't been found.
			if (DONE == 0)
			  begin
				// Report MISS to monitor and do nothing
			   cache_miss = cache_miss + 1;
			  end
		  	
		  	// Checking in Instuction Cache  
		  	for (i = 0; i < WAYS_IC; i = i + 1)
			  begin
				StoredHit_IC[Index][i] = 0;
			  end
			for (i = 0; i < WAYS_IC; i = i + 1)
			  begin
				if (DONE == 0)    // Line has not been found
				  begin
					if (Valid_IC[Index][i] == 1)    // Something exists in this line
					  begin
						if (StoredTag_IC[Index][i] == Tag)    // Check Tags
						  begin
							StoredHit_IC[Index][i] = 1;
							// Report HIT to monitor
							//HitCount = HitCount + 1.0;
							TempAddress = {Tag, Index, ByteSel};
							if (StoredMESI_IC[Index][i] == 2'b11)   // If the line is in Shared state and it is modified
							  begin
								// Report write-back to L2 Cache
								if(MODE==1)
								$display("Write back to L2 cache");
							  end
							 // make valid bit zero
							 Valid_IC[Index][i] = 0;
							// MESI bits set
							mesi_IC(N);
							// Adjust LRU bits
							LRUreplacement_IC();
							DONE = 1;
						  end
					  end
				  end
			  end
			// End of FOR loop signifies Capacity MISS (we don't have the line)
			// Only run this code if the line hasn't been found.
			if (DONE == 0)
			  begin
				// Report MISS to monitor and do nothing
			   cache_miss = cache_miss + 1;
			  end
			// Regardless, return DONE to 0
			DONE = 0;
		  end



4:begin
 // Clear stored hit values
			for (i = 0; i < WAYS_DC; i = i+1)
			  begin
				StoredHit_DC[Index][i] = 0;
			  end
			 for (i = 0; i < WAYS_DC; i = i + 1)
			  begin
				if (DONE == 0)    // Continue if the right line hasn't been found
				  begin
					if (Valid_DC[Index][i] == 1)    // Something exists in this line
					  begin
						if (StoredTag_DC[Index][i] == Tag)    // Correct tag found
						  begin
							if (StoredMESI_DC[Index][i] == 2'b01)   // Cache line is Modified
		 				        begin
								StoredHit_DC[Index][i] = 0;
								TempAddress = {Tag, Index, ByteSel};
							   if (MODE==1)
								begin
		 					    $display("Write data to Main Memory");
						            $display("Share data to L2");
		 					    $display("Processor gets RFO");
								end

								StoredMESI_DC[Index][i] = 2'b00;
								cache_miss = cache_miss + 0;
							    LRUreplacement_DC();
								DONE=1;
							  end
							else if(StoredMESI_DC[Index][i] == 2'b11 || StoredMESI_DC[Index][i] == 2'b10 || StoredMESI_DC[Index][i] == 2'b00)
							begin
								StoredHit_DC[Index][i] = 0;
								TempAddress = {Tag, Index, ByteSel};
							 if(MODE==1)
		 					 $display("Processor gets RFO");
						         StoredMESI_DC[Index][i] = 2'b00;
							 cache_miss = cache_miss + 0;
							 LRUreplacement_DC();
							 DONE = 1;
							  end
						end 
                    end
                end
            end
			  DONE = 0;
			end
 endcase
 end
endtask


// Task for Data Cache MESI coherence protocol

task mesi_DC;
	input [3:0]N;

	begin
		case (StoredMESI_DC[Index][i])
			Invalid:	begin
						if (N == 0 && StoredHit_DC[Index][i] == 1'b0 && StoredC_DC[Index][i] == 2'b11)
							StoredMESI_DC[Index][i] = Exclusive;
						else if (N == 0 && StoredHit_DC[Index][i] == 1'b0 && StoredC_DC[Index][i] == 2'b00)
						begin
							StoredMESI_DC[Index][i] = Exclusive;
						end
						else if (N == 1 && StoredC_DC[Index][i] == 2'b11 && StoredHit_DC[Index][i] == 0)
						begin
							StoredMESI_DC[Index][i] = Modified;
						end
						//else
							// No change
					end

			Modified:	begin
						if ((N == 3) && StoredHit_DC[Index][i] == 1'b1)
							begin
							// Write back to memory
							StoredMESI_DC[Index][i] = Invalid;
							end
						else if (StoredHit_DC[Index][i] == 1'b1)
							begin
							// Write back to memory
							StoredMESI_DC[Index][i] = Shared;
							end
						//else
							// No change
						end

			Exclusive:	begin
						if ((N == 3) && StoredHit_DC[Index][i] == 1'b1)
							StoredMESI_DC[Index][i] = Invalid;
						else if ( StoredHit_DC[Index][i] == 1'b1)
							StoredMESI_DC[Index][i] = Shared;
						//else
							// No change
						end

			Shared:		begin
						 if ((N == 3) && StoredHit_DC[Index][i] == 1'b1)
							StoredMESI_DC[Index][i] = Invalid;
						//else
							// No change
						end
		endcase
	end
endtask


// Task for Instuction Cache MESI coherence protocol

task mesi_IC;
    input [3:0]N;

    begin
        case (StoredMESI_IC[Index][i])
           Invalid: begin
                        if ((N == 2) && StoredHit_IC[Index][i] == 1'b0 && StoredC_IC[Index][i] == 2'b11)
                          StoredMESI_IC[Index][i] = Exclusive;//miss
                    end
					
           Modified: begin
                        if (N == 3 && StoredHit_IC[Index][i] == 1'b1)
                        begin
                        // Write back to memory
                        StoredMESI_IC[Index][i] = Invalid;
                        end
                    else if(N==2 && StoredC_IC[Index][i]== 2'b00 && StoredHit_IC [Index][i]==1'b1)
                       begin
                       StoredMESI_IC[Index][i] = Modified;
                       end
                    end

           Exclusive: begin
                         if(N==2 && StoredC_IC[Index][i]== 2'b00 && StoredHit_IC [Index][i]==1'b1)
                         begin
                         StoredMESI_IC[Index][i] = Exclusive;
                         end
                         else if (N == 3 && StoredHit_IC[Index][i] == 1'b1)
                         StoredMESI_IC[Index][i] = Invalid;
                      end

           Shared: begin
                      if(N==2 && StoredC_IC[Index][i]== 2'b00 && StoredHit_IC [Index][i]==1'b1)
                      begin
                      StoredMESI_IC[Index][i] = Shared;
                      end
                      else if ((N == 3) && StoredHit_IC[Index][i] == 1'b1)
                      StoredMESI_IC[Index][i] = Invalid;

                   end
        endcase
    end
endtask


// Task for initialization and re-initialization

task initialize;
	begin
	    for (i = 0; i < SETS; i = i + 1)
		begin
			for (j = 0; j < WAYS_DC; j = j + 1)
				begin
					Valid_DC[i][j] = 0;
					StoredTag_DC[i][j] = {12{1'b0}};
					LRUbits_DC[i][j] = 0;
					StoredHit_DC[i][j] = 0;
					StoredC_DC[i][j] = 2'bxx;
					StoredMESI_DC[i][j] = 0;
				  end
		end
    for (i = 0; i < SETS; i = i + 1)
		begin
			for (j = 0; j < WAYS_IC; j = j + 1)
				begin
					Valid_IC[i][j] = 0;
					StoredTag_IC[i][j] = {12{1'b0}};
					LRUbits_IC[i][j] = 0;
					StoredHit_IC[i][j] = 0;
					StoredC_IC[i][j] = 2'bxx;
					StoredMESI_IC[i][j] = 0;
				  end
		end
		
		DONE = 1'b0;
	end
endtask

// Task for LRU replacement strategy for Data Cache

task LRUreplacement_DC;
  begin
	for (j = 0; j < WAYS_DC; j = j + 1)
		begin
			if (j == i)
				LRUbits_DC[Index][j] = LRUbits_DC[Index][i];
            else if (LRUbits_DC[Index][j] <= LRUbits_DC[Index][i])
			begin
                LRUbits_DC[Index][j] = LRUbits_DC[Index][j] + 1;
			end
        end
    LRUbits_DC[Index][i] = 3'b000;
  end
endtask

// Task for LRU replacement strategy for Instruction Cache

task LRUreplacement_IC;
  begin
	for (j = 0; j < WAYS_IC; j = j + 1)
		begin
			if (j == i)
				LRUbits_IC[Index][j] = LRUbits_IC[Index][i];
            else if (LRUbits_IC[Index][j] <= LRUbits_IC[Index][i])
			begin
                LRUbits_IC[Index][j] = LRUbits_IC[Index][j] + 1;
			end
        end
    LRUbits_IC[Index][i] = 2'b00;
  end
endtask
  
// Function to generate output

task write_out;
	begin
	  // For Data Cache
	  
		for (i = 0; i < SETS; i = i + 1)
		begin
			if (Valid_DC[i][0] == 1)
				begin
				$display("Tag_DC           LRU_DC  MESI_DC ");
                                $display("%h     %b     %b  ", StoredTag_DC[i][0], LRUbits_DC[i][0], StoredMESI_DC[i][0]);
				end
			for (j = 1; j < WAYS_DC; j = j + 1)
			begin
			  if (Valid_DC[i][j] == 1)
				begin
				$display("%h     %b     %b ", StoredTag_DC[i][j], LRUbits_DC[i][j], StoredMESI_DC[i][j]);
				end
			end
		end
		
		// For Instruction Cache
		
				for (i = 0; i < SETS; i = i + 1)
		begin
			if (Valid_IC[i][0] == 1)
				begin
				$display("Tag_IC           LRU_IC  MESI_IC ");
				$display("%h     %b     %b ", StoredTag_IC[i][0], LRUbits_IC[i][0], StoredMESI_IC[i][0]);
				end
			for (j = 1; j < WAYS_IC; j = j + 1)
			begin
			  if (Valid_IC[i][j] == 1)
				begin
				$display("%h     %b     %b ", StoredTag_IC[i][j], LRUbits_IC[i][j], StoredMESI_IC[i][j]);
				end
			end
		end
	end
endtask
  
 endmodule