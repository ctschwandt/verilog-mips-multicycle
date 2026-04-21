//===========================================================================
// Name: Cole Schwandt
// File: tb.v
//
// test.mem layout
//
// word 0
// 10001100000000010000000000101000
// lw $1, 40($0)
// loads memory[10] into register 1
//
// word 1
// 10001100000000100000000000101100
// lw $2, 44($0)
// loads memory[11] into register 2
//
// word 2
// 00000000001000100001100000100000
// add $3, $1, $2
// register 3 = register 1 + register 2
//
// word 3
// 10101100000000110000000000110000
// sw $3, 48($0)
// stores register 3 into memory[12]
//
// word 4
// 00010000001000100000000000000010
// beq $1, $2, 2
// if register 1 equals register 2, branch ahead by 2 instructions
//
// word 5
// 00000000001000010000100000100000
// add $1, $1, $1
// register 1 = register 1 + register 1
// this should be skipped if the beq is taken
//
// word 6
// 00001000000000000000000000001000
// j 8
// jump to word 8
// this should also be skipped if the beq is taken
//
// word 7
// 00000000001000100000100000100000
// add $1, $1, $2
// register 1 = register 1 + register 2
// this should be skipped because of the jump or earlier branch
//
// word 8
// 00000000011000100000100000100000
// add $1, $3, $2
// register 1 = register 3 + register 2
//
// word 9
// 00000000000000000000000000000000
// nop-ish filler
// all zeros
//
// word 10
// 00000000000000000000000000000111
// data = 7
//
// word 11
// 00000000000000000000000000000111
// data = 7
//
// word 12
// 00000000000000000000000000000000
// data = 0 initially
// sw should overwrite this with register 3
//
// word 13
// 00000000000000000000000000000000
// data = 0
//
// word 14
// 00000000000000000000000000000000
// data = 0
//
// word 15
// 00000000000000000000000000000000
// data = 0
//===========================================================================

// module used to test main.v
module tb;
   reg clock;
   reg reset;

   main uut(.clock(clock), .reset(reset));
   
   initial begin
      clock = 0;
      forever #5 clock = ~clock;
   end

   initial begin
      reset = 1;
      #12;
      reset = 0;
   end

   initial begin
      $display("time  state  pc          ir          a           b           aluout      mdr         r1          r2          r3          mem10       mem12");
      $monitor("%4d   %2d   %h  %h  %h  %h  %h  %h  %h  %h  %h  %h  %h",
         $time,
         uut.mainControl.state,
         uut.PC,
         uut.IR,
         uut.A,
         uut.B,
         uut.ALUOut,
         uut.MDR,
         uut.registers.registers[1],
         uut.registers.registers[2],
         uut.registers.registers[3],
         uut.memory.memory[10],
         uut.memory.memory[12]
      );
   end

   initial begin
      #300;
      $display("");
      $display("r1 = %d", uut.registers.registers[1]);
      $display("r2 = %d", uut.registers.registers[2]);
      $display("r3 = %d", uut.registers.registers[3]);
      $display("mem[10] = %d", uut.memory.memory[10]);
      $display("mem[12] = %d", uut.memory.memory[12]);
      $finish;
   end
endmodule
