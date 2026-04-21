OUT = cpu.out
SRC = tb.v main.v

run:
	iverilog -o $(OUT) $(SRC)
	vvp $(OUT)

clean:
	rm -f $(OUT)
