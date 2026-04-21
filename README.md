# verilog-mips-multicycle

a multicycle mips cpu implemented in verilog. this project simulates a subset of the mips architecture using a control unit + datapath design based on the standard multicycle model.

## overview

this processor executes instructions over multiple clock cycles, allowing hardware components like the alu to be reused across instruction stages. this reduces hardware complexity compared to a single-cycle design.

the implementation follows the multicycle architecture described in figure e4.5.4 and supports:

- r-type: add, sub, and, or, slt
- memory: lw, sw
- control flow: beq, j

## architecture

the cpu is built using the standard multicycle datapath with the following internal registers:

- pc
- ir
- mdr
- a
- b
- aluout

each instruction is executed across multiple stages:

1. instruction fetch
2. decode / register fetch
3. execute / address calculation
4. memory access / r-type completion
5. write-back for lw

control is implemented as a finite state machine with 10 states.

## files

- `main.v` – full multicycle mips cpu implementation in one file, including:
  - alu
  - alu control
  - control finite state machine
  - memory
  - register file
  - top-level datapath
- `tb.v` – testbench for simulation
- `test.mem` – binary machine code / data loaded into memory
- `makefile` – build and run commands for iverilog

## example program

the default test program demonstrates:

- loading values from memory
- performing arithmetic
- storing results
- branching with beq
- jumping with j