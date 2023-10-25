vlib work
vlog -reportprogress 300 -work work final2.v 
vsim -gui -GMODE=1 work.L1_split_cache final2.v
run -all
quit -sim
