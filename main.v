//============================================================================
// Name: Cole Schwandt
// File: main.v
//
// High Level Overview
// --------------------------------
// The reason for a multicycle instruction implementation for an architecture is two-fold. The first benefit is
// being able to make components reusable, reducing the amount of separate components you need (one ALU
// can perform all the necessary tasks for any instruction you perform). The multicycle implementation also
// allows for faster clock cycles, because you do not need to finish every part of the task in one cycle (in the
// single cycle implementation, you will need to have the clock be slow enough to allow the longest possible
// cycle to finish, which is a lw instruction for the MIPS subset we are implementing).
// In the multicycle implementation, there are generally five steps of computation, which I list here:
// 1. Instruction fetch step: Increment PC to the next instruction (which is PC ← PC+4). Load the instruction
// (from memory) into the instruction register. [Here might be a good point to think about how loading
// into memory takes some time, forcing the clock cycle to be slower. One method that architectures use
// to get around this is to have several registers in IR when you load the next instruction, you also load the
// next few instructions, preventing you from having to go back to memory every time you need another
// instruction, a technique called caching.
// 2. Instruction decode and register fetch step: In this step, you send the op-code Op to the control (which
// immediately starts decoding it), and send Reg[IR[25:21]] to A and Reg[IR[20:16]] to B. The other
// thing you do is immediately calculate what the branch location would be if this is a branch instruction
// (this is done so that branch can be done immediately in the following step). In otherwords, ALUOut ←
// PC + (sign-extend(IR[15:0]<<2)
// 3. Execution, memory address computation, or branch completion: in this step, you execute (if for
// example if it is an R-type instruction, you compute the result) if it is a memory access instruction
// (such as in lw or sw) you will compute the address of access. The instruction class will determine what
// inputs will be given to the ALU for computation at this point.
// 4. Memory access or R-type instruction completion step: In this step, you will finish the R-type instruction, and sw instruction. In this step, we load MDR with the value in location in memory computed in
// the previous step.
// 5. Memory read completion step: The only instruction that will make it to this step in our implementation
// is the lw instruction. In this step, we load MDR into the register as required by the lw instruction
//============================================================================

// alu
// does the arithmetic and logic work
module ALU(A, B, ALUControl, Result, Zero);
   input  [31:0] A;
   input [31:0]  B;
   input [3:0]   ALUControl;

   output reg [31:0] Result;
   output            Zero;

   // used by beq
   // if the subtraction result is 0 then the values were equal
   assign Zero = (Result == 32'b0);

   // looks at opcode and does whatever operations goes with that opcode
   always @(*) begin
      case (ALUControl)
        4'b0000: Result = A & B;      // and
        4'b0001: Result = A | B;      // or
        4'b0010: Result = A + B;      // add
        4'b0110: Result = A - B;      // subtract
        4'b0111: begin                // slt
           if ($signed(A) < $signed(B))
             Result = 32'd1;
           else
             Result = 32'd0;
        end
        4'b1100: Result = ~(A | B);   // nor
        default: Result = 32'b0;      // safe default
      endcase
   end
endmodule


// alu control
// turns aluop and funct into the actual 4-bit alu control value
module ALUControl(ALUOp, funct, ALUControlOut);
   input  [1:0] ALUOp;
   input [5:0]  funct;

   output reg [3:0] ALUControlOut;

   always @(*) begin
      case (ALUOp)
        2'b00: ALUControlOut = 4'b0010; // add for fetch lw sw and branch target calc
        2'b01: ALUControlOut = 4'b0110; // subtract for beq compare

        // r-type instruction
        // look at funct to decide the real alu operation
        2'b10: begin
           case (funct)
             6'b100000: ALUControlOut = 4'b0010; // add
             6'b100010: ALUControlOut = 4'b0110; // sub
             6'b100100: ALUControlOut = 4'b0000; // and
             6'b100101: ALUControlOut = 4'b0001; // or
             6'b101010: ALUControlOut = 4'b0111; // slt
             default:   ALUControlOut = 4'b0010; // safe default
           endcase
        end

        default: ALUControlOut = 4'b0010;
      endcase
   end
endmodule


// main control
// this is the multicycle state machine
// it turns on the right control signals for each step
module Control(clock, reset, Op,
               PCWriteCond, PCWrite, IorD, MemRead, MemWrite,
               MemtoReg, IRWrite, PCSource, ALUOp, ALUSrcB,
               ALUSrcA, RegWrite, RegDst, state);

   input        clock;
   input        reset;
   input [5:0]  Op;

   output reg   PCWriteCond;
   output reg   PCWrite;
   output reg   IorD;
   output reg   MemRead;
   output reg   MemWrite;
   output reg   MemtoReg;
   output reg   IRWrite;
   output reg [1:0] PCSource;
   output reg [1:0] ALUOp;
   output reg [1:0] ALUSrcB;
   output reg       ALUSrcA;
   output reg       RegWrite;
   output reg       RegDst;
   output reg [3:0] state;
   
   // opcodes
   parameter        OP_RTYPE = 6'b000000;
   parameter        OP_LW = 6'b100011;
   parameter        OP_SW = 6'b101011;
   parameter        OP_BEQ = 6'b000100;
   parameter        OP_J = 6'b000010;

   // state enums
   // 1. State 0 (Step 1 of all instructions): In this state, the very first thing we do is increment the program
   // counter by 4. We have one ALU, so we must select the correct sources for the ALU. After this, we
   // select the instruction at memory location PC and load the instruction into IR. (Go to state 1)
   // 2. State 1 (Step 2 of all instructions): In this state IR[31:26] is loaded into the Op port of control.
   // IR[25:21] and IR[20:16] are used to read from Registers and store the values in A and B. IR[15:0]
   // is sign-extended to 32-bits. One goes to data port 2 of the mux, and a shifted by 2-bit version is sent to
   // port 3. The mux selects port 3 for ALUSrcB and port 0 for ALUSrcA to compute the Address of beq.
   // The ALUOp is set to 00 to have the ALU add. (ALUOp is used by the ALUControl) to control the
   // ALU). (Go to state 2 if Op is lw or sw, Go to state 6 if Op is 000000 (R-type instruction),
   // Go to state 8 if Op is beq, Go to state 9 if Op is j)
   // 3. State 2 (Step 3 of Memory instructions) Compute Address. ALUSrcB is 10 and ALUSrcA is 1 using
   // the value loaded into A on the previous clock cycle. (Go to state 3 if Op is lw, Go to state 5 if
   // Op is sw)
   // 4. State 3 (Step 4 of lw) Read from memory, select Data rather than instruction (IorD = 1) (Go to
   // state 4)
   // 5. State 4 (Step 5 of lw) Write MDR to register represented in IR[20:16] (Go to state 0)
   // 6. State 5 (Step 4 of sw) Write the value of B to memory. (Go to state 0)
   // 7. State 6 (Step 3 of R-type instructions) Compute the function on the values loaded into registers
   // (IR[5:0] A and B from the previous cycle. (Go to state 7)
   // 8. State 7 (Step 4 of R-type instructions) Write the value in ALUOut to the register in (IR[15:11]) (Go
   // to state 0)
   // 9. State 8 (Step 3 of Beq instruction) Compute the equality of the values stored in register A and B in the
   // previous clock cycle. (Go to state 0)
   // 10. State 9 (Step 3 of Jump Instruction) Update PC based on the jump address. Remember the jump
   // address computation (you use the first 4 bits of PC, and the 26-bits of jump address shifted by 2).
   // (Go to state 0)
   //=============================
   parameter        STATE_FETCH = 4'd0;
   parameter        STATE_DECODE = 4'd1;
   parameter        STATE_MEM_ADDR = 4'd2;
   parameter        STATE_LW_READ = 4'd3;
   parameter        STATE_LW_WRITE = 4'd4;
   parameter        STATE_SW_WRITE = 4'd5;
   parameter        STATE_R_EXECUTE = 4'd6;
   parameter        STATE_R_WRITE = 4'd7;
   parameter        STATE_BEQ_EXECUTE = 4'd8;
   parameter        STATE_J_EXECUTE = 4'd9;

   // output logic
   // start with everything off
   // then turn on only what the current state needs
   always @(*) begin
      PCWriteCond = 1'b0;
      PCWrite = 1'b0;
      IorD = 1'b0;
      MemRead = 1'b0;
      MemWrite = 1'b0;
      MemtoReg = 1'b0;
      IRWrite = 1'b0;
      PCSource = 2'b00;
      ALUOp = 2'b00;
      ALUSrcB = 2'b00;
      ALUSrcA = 1'b0;
      RegWrite = 1'b0;
      RegDst = 1'b0;

      case (state)
        // step 1 of every instruction
        // fetch instruction
        // compute pc + 4
        // write instruction into ir
        STATE_FETCH: begin
           MemRead = 1'b1;
           IRWrite = 1'b1;
           PCWrite = 1'b1;
           ALUSrcA = 1'b0;
           ALUSrcB = 2'b01;
           ALUOp = 2'b00;
           PCSource = 2'b00;
        end

        // step 2 of every instruction
        // read rs and rt into a and b
        // also compute possible branch target and store it in aluout
        STATE_DECODE: begin
           ALUSrcA = 1'b0;
           ALUSrcB = 2'b11;
           ALUOp   = 2'b00;
        end

        // step 3 of lw and sw
        // compute effective address using a + immediate
        STATE_MEM_ADDR: begin
           ALUSrcA = 1'b1;
           ALUSrcB = 2'b10;
           ALUOp = 2'b00;
        end

        // step 4 of lw
        // read memory at the address stored in aluout
        STATE_LW_READ: begin
           MemRead = 1'b1;
           IorD = 1'b1;
        end

        // step 5 of lw
        // write mdr into rt
        STATE_LW_WRITE: begin
           RegWrite = 1'b1;
           RegDst = 1'b0;
           MemtoReg = 1'b1;
        end

        // step 4 of sw
        // write b into memory
        STATE_SW_WRITE: begin
           MemWrite = 1'b1;
           IorD = 1'b1;
        end

        // step 3 of r-type
        // do the alu operation on a and b
        STATE_R_EXECUTE: begin
           ALUSrcA = 1'b1;
           ALUSrcB = 2'b00;
           ALUOp = 2'b10;
        end

        // step 4 of r-type
        // write aluout into rd
        STATE_R_WRITE: begin
           RegWrite = 1'b1;
           RegDst = 1'b1;
           MemtoReg = 1'b0;
        end

        // step 3 of beq
        // subtract a and b
        // if zero is 1 then pc gets the branch target from aluout
        STATE_BEQ_EXECUTE: begin
           ALUSrcA = 1'b1;
           ALUSrcB = 2'b00;
           ALUOp = 2'b01;
           PCWriteCond = 1'b1;
           PCSource = 2'b01;
        end

        // step 3 of j
        // load the jump address into pc
        STATE_J_EXECUTE: begin
           PCWrite = 1'b1;
           PCSource = 2'b10;
        end

        default:
          ;
      endcase
   end

   // state register (states changes on positive edge)
   always @(posedge clock) begin
      if (reset == 1'b1) begin
         state <= STATE_FETCH;
      end
      else begin
         case (state)
           // after fetch always go to decode
           STATE_FETCH:
             state <= STATE_DECODE;

           // decode chooses the next state based on opcode
           STATE_DECODE: begin
              case (Op)
                OP_LW: 
                  state <= STATE_MEM_ADDR;
                OP_SW:
                  state <= STATE_MEM_ADDR;
                OP_RTYPE:
                  state <= STATE_R_EXECUTE;
                OP_BEQ:
                  state <= STATE_BEQ_EXECUTE;
                OP_J:
                  state <= STATE_J_EXECUTE;
                default:  
                  state <= STATE_FETCH;
              endcase
           end

           // after computing an address
           // lw goes to memory read
           // sw goes to memory write
           STATE_MEM_ADDR: begin
              case (Op)
                OP_LW:
                  state <= STATE_LW_READ;
                default:
                  state <= STATE_SW_WRITE;
              endcase
           end

           STATE_LW_READ:
             state <= STATE_LW_WRITE;

           STATE_LW_WRITE:
             state <= STATE_FETCH;

           STATE_SW_WRITE:
             state <= STATE_FETCH;

           STATE_R_EXECUTE:
             state <= STATE_R_WRITE;

           STATE_R_WRITE:
             state <= STATE_FETCH;

           STATE_BEQ_EXECUTE:
             state <= STATE_FETCH;

           STATE_J_EXECUTE:
             state <= STATE_FETCH;

           default:
             state <= STATE_FETCH;
         endcase
      end
   end
endmodule


// memory
// one shared memory for both instructions and data
module Memory(clock, MemRead, MemWrite, address, writeData, readData);
   input         clock;
   input         MemRead;
   input         MemWrite;
   input [31:0]  address;
   input [31:0]  writeData;

   output reg [31:0] readData;

   reg [31:0]        memory [0:255];
   integer           i;

   initial begin
      // clear memory first
      for (i = 0; i < 256; i = i + 1)
        memory[i] = 32'b0;

      // load program and data
      $readmemb("test.mem", memory);
   end

   // read
   always @(*) begin
      if (MemRead == 1'b1)
        readData = memory[address[9:2]];
      else
        readData = 32'b0;
   end

   // write
   always @(posedge clock) begin
      if (MemWrite == 1'b1)
        memory[address[9:2]] <= writeData;
   end
endmodule


// register file
// 32 general-purpose mips registers
// reads are combinational
// writes happen on the positive edge
module Registers(clock, reset,
                 ReadRegister1, ReadRegister2,
                 WriteRegister, WriteData, RegWrite,
                 ReadData1, ReadData2);

   input         clock;
   input         reset;
   input [4:0]   ReadRegister1;
   input [4:0]   ReadRegister2;
   input [4:0]   WriteRegister;
   input [31:0]  WriteData;
   input         RegWrite;

   output [31:0] ReadData1;
   output [31:0] ReadData2;

   reg [31:0]    registers [0:31];
   integer       i;

   assign ReadData1 = registers[ReadRegister1];
   assign ReadData2 = registers[ReadRegister2];

   always @(posedge clock) begin
      if (reset == 1'b1) begin
         // clear all registers
         for (i = 0; i < 32; i = i + 1)
           registers[i] <= 32'b0;
      end
      else begin
         // write if allowed
         // but never write register 0
         if (RegWrite == 1'b1) begin
            if (WriteRegister != 5'b00000)
              registers[WriteRegister] <= WriteData;
         end

         // register 0 is always 0
         registers[0] <= 32'b0;
      end
   end
endmodule


// this is where all the pieces are connected together
module main(clock, reset);
   input clock;
   input reset;

   // internal multicycle registers from the figure
   reg [31:0] PC;
   reg [31:0] IR;
   reg [31:0] MDR;
   reg [31:0] A;
   reg [31:0] B;
   reg [31:0] ALUOut;

   // control signals
   wire       PCWriteCond;
   wire       PCWrite;
   wire       IorD;
   wire       MemRead;
   wire       MemWrite;
   wire       MemtoReg;
   wire       IRWrite;
   wire [1:0] PCSource;
   wire [1:0] ALUOp;
   wire [1:0] ALUSrcB;
   wire       ALUSrcA;
   wire       RegWrite;
   wire       RegDst;
   wire [3:0] state;

   // instruction fields
   wire [5:0] opcode;
   wire [4:0] rs;
   wire [4:0] rt;
   wire [4:0] rd;
   wire [5:0] funct;

   // memory path
   reg [31:0] memoryAddress;
   wire [31:0] memoryData;

   // register writeback path
   wire [31:0] registerReadData1;
   wire [31:0] registerReadData2;
   reg [4:0]   writeRegister;
   reg [31:0]  writeData;

   // immediate and jump helpers
   wire [31:0] signExtendedImmediate;
   wire [31:0] shiftedImmediate;
   wire [31:0] jumpAddress;

   // alu path
   reg [31:0]  ALUInputA;
   reg [31:0]  ALUInputB;
   wire [3:0]  ALUControlSignal;
   wire [31:0] ALUResult;
   wire        Zero;

   // pc update
   wire        PCEnable;
   reg [31:0]  nextPC;

   // decode fields from the instruction register
   assign opcode = IR[31:26];
   assign rs     = IR[25:21];
   assign rt     = IR[20:16];
   assign rd     = IR[15:11];
   assign funct  = IR[5:0];

   // sign extend the immediate field
   assign signExtendedImmediate = {{16{IR[15]}}, IR[15:0]};

   // shifted version used for branch target calculation
   assign shiftedImmediate = {signExtendedImmediate[29:0], 2'b00};

   // jump address
   // by the time jump executes, pc already holds pc + 4
   assign jumpAddress = {PC[31:28], IR[25:0], 2'b00};

   // final pc write enable
   // unconditional write or conditional write with zero
   assign PCEnable = PCWrite | (PCWriteCond & Zero);

   // iord mux
   // 0 means use pc for instruction fetch
   // 1 means use aluout for data access
   always @(*) begin
      case (IorD)
        1'b0: memoryAddress = PC;
        1'b1: memoryAddress = ALUOut;
      endcase
   end

   // regdst mux
   // 0 means write rt
   // 1 means write rd
   always @(*) begin
      case (RegDst)
        1'b0: writeRegister = rt;
        1'b1: writeRegister = rd;
      endcase
   end

   // memtoreg mux
   // 0 means write aluout
   // 1 means write mdr
   always @(*) begin
      case (MemtoReg)
        1'b0: writeData = ALUOut;
        1'b1: writeData = MDR;
      endcase
   end

   // alusrca mux
   // 0 means use pc
   // 1 means use a
   always @(*) begin
      case (ALUSrcA)
        1'b0: ALUInputA = PC;
        1'b1: ALUInputA = A;
      endcase
   end

   // alusrcb mux
   // 00 -> b
   // 01 -> constant 4
   // 10 -> sign-extended immediate
   // 11 -> shifted immediate
   always @(*) begin
      case (ALUSrcB)
        2'b00: ALUInputB = B;
        2'b01: ALUInputB = 32'd4;
        2'b10: ALUInputB = signExtendedImmediate;
        2'b11: ALUInputB = shiftedImmediate;
      endcase
   end

   // pcsource mux
   // 00 -> alu result
   // 01 -> aluout
   // 10 -> jump address
   always @(*) begin
      case (PCSource)
        2'b00: nextPC = ALUResult;
        2'b01: nextPC = ALUOut;
        2'b10: nextPC = jumpAddress;
        default: nextPC = ALUResult;
      endcase
   end

   // main control unit
   Control mainControl(clock, reset, opcode,
                       PCWriteCond, PCWrite, IorD, MemRead, MemWrite,
                       MemtoReg, IRWrite, PCSource, ALUOp, ALUSrcB,
                       ALUSrcA, RegWrite, RegDst, state);

   // shared memory
   // for sw the value being written comes from b
   Memory memory(clock, MemRead, MemWrite, memoryAddress, B, memoryData);

   // programmer-visible register file
   Registers registers(clock, reset,
                       rs, rt,
                       writeRegister, writeData, RegWrite,
                       registerReadData1, registerReadData2);

   // alu control
   ALUControl aluControl(ALUOp, funct, ALUControlSignal);

   // alu
   ALU alu(ALUInputA, ALUInputB, ALUControlSignal, ALUResult, Zero);

   // update internal registers on the clock edge
   always @(posedge clock) begin
      if (reset == 1'b1) begin
         PC <= 32'b0;
         IR <= 32'b0;
         MDR <= 32'b0;
         A <= 32'b0;
         B <= 32'b0;
         ALUOut <= 32'b0;
      end
      else begin
         // update pc when the control logic says to
         if (PCEnable == 1'b1)
           PC <= nextPC;

         // write ir only during instruction fetch
         if (IRWrite == 1'b1)
           IR <= memoryData;

         // these registers update every cycle in this multicycle design
         MDR <= memoryData;
         A <= registerReadData1;
         B <= registerReadData2;
         ALUOut <= ALUResult;
      end
   end
endmodule
