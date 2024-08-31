`default_nettype none

typedef enum bit [2:0] {
  ALU_ADD = 3'b000,
  ALU_ADC = 3'b001,
  ALU_SUB = 3'b010,
  ALU_SBC = 3'b011,
  ALU_AND = 3'b100,
  ALU_ORR = 3'b101,
  ALU_XOR = 3'b110,
  ALU_BTC = 3'b111
} AluCode;

typedef enum bit [3:0] {
  COND_EQ = 4'b0000,
  COND_NE = 4'b0001,
  COND_CS = 4'b0010,
  COND_CC = 4'b0011,
  COND_MI = 4'b0100,
  COND_PL = 4'b0101,
  COND_VS = 4'b0110,
  COND_VC = 4'b0111,
  COND_HI = 4'b1000,
  COND_LS = 4'b1001,
  COND_GE = 4'b1010,
  COND_LT = 4'b1011,
  COND_GT = 4'b1100,
  COND_LE = 4'b1101,
  COND_AL = 4'b1110
} ConditionCode;

typedef struct {
  Exception     exception;
  Word          linkAddress;
  bit           memoryAccess;
  bit           readWrite;
  bit           postIncOffset;
  bit           writebackOffset;
  bit           halfAccess;
  bit           byteAccess;
  bit           getPsr;
  bit           setPsrFlagsOnly;
  bit           setPsr;
  bit           shiftRight;
  bit           shiftArithmetic;
  bit           branch;
  bit           link;
  ConditionCode branchCondition;
  AluCode       aluCode;
  RegTag        loadStoreRegTag;
  Word          loadStoreValue;
  RegTag        baseRegTag;
  Word          baseValue;
  RegTag        shiftRegTag;
  bit [7:0]     shiftValue;
  RegTag        offsetRegTag;
  Word          offsetValue;
  StatusFlags   psrValue;
} ExSignals;

module ExecuteStage (
  exSignals,
  exStall,
  instrIsLoad, instrSetsControlFlags,
  branchAddress, branchEnable,
  exception,
  resultRegTag,
  memForwardResultRegTag, memForwardResultValue,
  memForwardAutoIncRegTag, memForwardAutoIncValue,
  memForwardPsrValue, memForwardPsrValid,
  wbForwardResultRegTag, wbForwardResultValue,
  wbForwardAutoIncRegTag, wbForwardAutoIncValue,
  wbForwardPsrValue, wbForwardPsrValid,
  memSignals
);

  // ============================================================================
  // PORT DECLARATIONS
  // ============================================================================

  input  ExSignals  exSignals;
  // input  bit        exStall;
  output bit        instrIsLoad;
  output bit        instrSetsControlFlags;
  output Word       branchAddress;
  output bit        branchEnable;
  output Exception  exception;
  output RegTag     resultRegTag;
  input  RegTag     memForwardResultRegTag;
  input  Word       memForwardResultValue;
  input  RegTag     memForwardAutoIncRegTag;
  input  Word       memForwardAutoIncValue;
  input  Word       memForwardPsrValue;
  input  bit        memForwardPsrValid;
  input  RegTag     wbForwardResultRegTag;
  input  Word       wbForwardResultValue;
  input  RegTag     wbForwardAutoIncRegTag;
  input  Word       wbForwardAutoIncValue;
  input  Word       wbForwardPsrValue;
  input  bit        wbForwardPsrValid;
  output MemSignals memSignals;

  
  // ============================================================================
  // OPERAND FORWARDING
  // ============================================================================

  Word      loadStoreValue;
  Word      baseValue;
  bit [7:0] shiftValue;
  Word      offsetValue;

  always_comb begin
    if      (exSignals.loadStoreRegTag == R0)                      loadStoreValue = exSignals.loadStoreValue;
    else if (exSignals.loadStoreRegTag == memForwardResultRegTag)  loadStoreValue = memForwardResultValue;
    else if (exSignals.loadStoreRegTag == memForwardAutoIncRegTag) loadStoreValue = memForwardAutoIncValue;
    else if (exSignals.loadStoreRegTag == wbForwardResultRegTag)   loadStoreValue = wbForwardResultValue;
    else if (exSignals.loadStoreRegTag == wbForwardAutoIncRegTag)  loadStoreValue = wbForwardAutoIncValue;
    else                                                           loadStoreValue = exSignals.loadStoreValue;

    if      (exSignals.baseRegTag == R0)                           baseValue      = exSignals.baseValue;
    else if (exSignals.baseRegTag == memForwardResultRegTag)       baseValue      = memForwardResultValue;
    else if (exSignals.baseRegTag == memForwardAutoIncRegTag)      baseValue      = memForwardAutoIncValue;
    else if (exSignals.baseRegTag == wbForwardResultRegTag)        baseValue      = wbForwardResultValue;
    else if (exSignals.baseRegTag == wbForwardAutoIncRegTag)       baseValue      = wbForwardAutoIncValue;
    else                                                           baseValue      = exSignals.baseValue;

    if      (exSignals.offsetRegTag == R0)                         offsetValue    = exSignals.offsetValue;
    else if (exSignals.offsetRegTag == memForwardResultRegTag)     offsetValue    = memForwardResultValue;
    else if (exSignals.offsetRegTag == memForwardAutoIncRegTag)    offsetValue    = memForwardAutoIncValue;
    else if (exSignals.offsetRegTag == wbForwardResultRegTag)      offsetValue    = wbForwardResultValue;
    else if (exSignals.offsetRegTag == wbForwardAutoIncRegTag)     offsetValue    = wbForwardAutoIncValue;
    else                                                           offsetValue    = exSignals.offsetValue;

    if      (exSignals.shiftRegTag == R0)                          shiftValue     = exSignals.shiftValue;
    else if (exSignals.shiftRegTag == memForwardResultRegTag)      shiftValue     = memForwardResultValue;
    else if (exSignals.shiftRegTag == memForwardAutoIncRegTag)     shiftValue     = memForwardAutoIncValue;
    else if (exSignals.shiftRegTag == wbForwardResultRegTag)       shiftValue     = wbForwardResultValue;
    else if (exSignals.shiftRegTag == wbForwardAutoIncRegTag)      shiftValue     = wbForwardAutoIncValue;
    else                                                           shiftValue     = exSignals.shiftValue;

    if      (memForwardPsrValid && memForwardPsrValue.s == exSignals.psrValue.s) psrValue = memForwardPsrValue;
    else if (wbForwardPsrValid  && wbForwardPsrValue.s  == exSignals.psrValue.s) psrValue = wbForwardPsrValue;
    else                                                                         psrValue = exSignals.psrValue;
  end


  // ============================================================================
  // BRANCH CONDITION
  // ============================================================================

  bit branchConditionMet;

  always_comb begin
    case (exSignals.branchCondition)
      COND_EQ: branchConditionMet =  psrValue.z;
      COND_NE: branchConditionMet = ~psrValue.z;
      COND_CS: branchConditionMet =  psrValue.c;
      COND_CC: branchConditionMet = ~psrValue.c;
      COND_MI: branchConditionMet =  psrValue.n;
      COND_PL: branchConditionMet = ~psrValue.n;
      COND_VS: branchConditionMet =  psrValue.v;
      COND_VC: branchConditionMet = ~psrValue.v;
      COND_HI: branchConditionMet =  psrValue.c & ~psrValue.z;
      COND_LS: branchConditionMet = ~psrValue.c &  psrValue.z;
      COND_GE: branchConditionMet =  psrValue.n == psrValue.v;
      COND_LT: branchConditionMet =  psrValue.n != psrValue.v;
      COND_GT: branchConditionMet = (psrValue.n == psrValue.v) & ~psrValue.z;
      COND_LE: branchConditionMet = (psrValue.n != psrValue.v) |  psrValue.z;
      COND_AL: branchConditionMet = 1'b1;
      4'b1111: branchConditionMet = 1'b0;
    endcase
  end


  // ============================================================================
  // SHIFT OFFSET
  // ============================================================================

  Word shiftResult;
  bit  shiftCarry;

  always_comb begin
    casez ({ exSignals.shiftDir, exSignals.shiftAri, (shiftValue == 0) })
      3'b0?0: { shiftCarry, shiftResult } = { psrValue.c, offsetValue };  // LSL #0 preserves c flag
      3'b0?1: { shiftCarry, shiftResult } = offsetValue <<  shiftValue-1; // LSL #1-255
      3'b100: { shiftResult, shiftCarry } = offsetValue >>  32-1;         // LSR #0 encodes LSR #32
      3'b101: { shiftResult, shiftCarry } = offsetValue >>  shiftValue-1; // LSR #0-255
      3'b110: { shiftResult, shiftCarry } = offsetValue >>> 32-1;         // ASR #0 encodes ASR #32
      3'b111: { shiftResult, shiftCarry } = offsetValue >>> shiftValue-1; // ASR #0-255
    endcase
  end


  // ============================================================================
  // ALU OPERATION
  // ============================================================================

  Word        aluResult;
  bit         aluOverflow, aluCarry;
  StatusFlags aluResultFlags;

  always_comb begin
    case (exSignals.aluCode)
      ALU_ADD: { aluCarry, aluResult } = baseValue +  shiftResult;
      ALU_ADC: { aluCarry, aluResult } = baseValue +  shiftResult + psrValue.c;
      ALU_SUB: { aluCarry, aluResult } = baseValue + ~shiftResult + 1'b1;
      ALU_SBC: { aluCarry, aluResult } = baseValue + ~shiftResult + psrValue.c;
      ALU_AND: { aluCarry, aluResult } = { shiftCarry, baseValue &  offsetValue };
      ALU_ORR: { aluCarry, aluResult } = { shiftCarry, baseValue |  offsetValue };
      ALU_XOR: { aluCarry, aluResult } = { shiftCarry, baseValue ^  offsetValue };
      ALU_BTC: { aluCarry, aluResult } = { shiftCarry, baseValue & ~offsetValue };
    endcase
  end

  assign aluOverflow = ( baseValue[31] &  shiftResult[31] & ~aluResult[31])
                     | (~baseValue[31] & ~shiftResult[31] &  aluResult[31]);

  always_comb begin
    aluResultFlags.c = aluCarry;
    aluResultFlags.z = (aluResult == 0);
    aluResultFlags.n = aluResult[31];
    aluResultFlags.v = (exSignals.aluCode <= ALU_SBC) ? aluOverflow : psrValue.v;
  end


  // ============================================================================
  // SIGNALS TO MEMORY ACCESS STAGE
  // ============================================================================

  // TODO optimize to pass through values that don't need to be zeroed
  //      eliminate redundancies
  always_comb begin
    // if (exSignals.stall) begin
    //   // TODO I don't think this is correct. branches and exceptions can
    //   // probably happen even if waiting for memory access stage. They will
    //   // fetch from the new PC once the access has finished?
    //   instrIsLoad           = 1'b0;
    //   instrSetsControlFlags = 1'b0;
    //   branchAddress         = 32'h00000000;
    //   branchEnable          = 1'b0;
    //   exception             = EXCEPT_NONE;
    //   resultRegTag          = R0;
    //   memSignals = '{
    //     linkAddress      : exSignals.linkAddress,
    //     default             : 0
    //   };
    // end else
    if (exSignals.exception != EXCEPT_NONE) begin
      instrIsLoad           = 1'b0;
      instrSetsControlFlags = 1'b0;
      branchAddress         = 32'h00000000;
      branchEnable          = 1'b0;
      exception             = exSignals.exception;
      resultRegTag          = R0;
      memSignals = '{
        linkAddress         : exSignals.linkAddress,
        default             : 0
      };
    end else if (exSignals.branch) begin
      instrIsLoad           = 1'b0;
      instrSetsControlFlags = 1'b0;
      branchAddress         = aluResult;
      branchEnable          = branchConditionMet;
      exception             = EXCEPT_NONE;
      resultRegTag          = exSignals.loadStoreRegTag;
      memSignals = '{
        linkAddress         : exSignals.linkAddress,
        memoryAccess        : 1'b0,
        readWrite           : 1'b0,
        halfAccess          : 1'b0,
        byteAccess          : 1'b0,
        memoryAccessAddress : 32'h00000000,
        loadRegTag          : R0,
        storeValue          : 32'h00000000,
        aluResultRegTag     : exSignals.loadStoreRegTag,
        aluResultValue      : exSignals.loadStoreValue,
        psrValue            : 8'h00,
        psrUpdated          : 1'b0
      };
    end else if (exSignals.getPsr) begin
      instrIsLoad           = 1'b0;
      instrSetsControlFlags = 1'b0;
      branchAddress         = 32'h00000000;
      branchEnable          = 1'b0;
      exception             = EXCEPT_NONE;
      resultRegTag          = exSignals.loadStoreRegTag;
      memSignals = '{
        linkAddress         : exSignals.linkAddress,
        memoryAccess        : 1'b0,
        readWrite           : 1'b0,
        halfAccess          : 1'b0,
        byteAccess          : 1'b0,
        memoryAccessAddress : 32'h00000000,
        loadRegTag          : R0,
        storeValue          : 32'h00000000,
        aluResultRegTag     : exSignals.loadStoreRegTag,
        aluResultValue      : { 24'h000000, exSignals.psrValue },
        psrValue            : 8'h00,
        psrUpdated          : 1'b0
      };
    end else if (exSignals.setPsr) begin
      instrIsLoad           = 1'b0;
      instrSetsControlFlags = !exSignals.setPsrFlagsOnly;
      branchAddress         = 32'h00000000;
      branchEnable          = 1'b0;
      exception             = EXCEPT_NONE;
      resultRegTag          = R0;
      memSignals = '{
        linkAddress         : exSignals.linkAddress,
        memoryAccess        : 1'b0,
        readWrite           : 1'b0,
        halfAccess          : 1'b0,
        byteAccess          : 1'b0,
        memoryAccessAddress : 32'h00000000,
        loadRegTag          : R0,
        storeValue          : 32'h00000000,
        aluResultRegTag     : R0,
        aluResultValue      : 32'h00000000,
        psrValue            : (exSignals.setPsrFlagsOnly) ? { psrValue[7:4], exSignals.offsetValue[3:0] } : exSignals.offsetValue[7:0],
        psrUpdated          : 1'b1
      };
    end else if (exSignals.memoryAccess) begin
      var bit writeback = (exSignals.postIncOffset || exSignals.writebackOffset);
      instrIsLoad           = (exSignals.readWrite == 1'b0);
      instrSetsControlFlags = (exSignals.setPsr    == 1'b1);
      branchAddress         = 32'h00000000;
      branchEnable          = 1'b0;
      exception             = EXCEPT_NONE;
      resultRegTag          = exSignals.loadStoreRegTag;
      memSignals = '{
        linkAddress         : exSignals.linkAddress,
        memoryAccess        : exSignals.memoryAccess,
        readWrite           : exSignals.readWrite,
        halfAccess          : exSignals.halfAccess,
        byteAccess          : exSignals.byteAccess,
        memoryAccessAddress : (exSignals.postIncOffset)     ? baseValue                 : aluResult,
        loadRegTag          : (exSignals.readWrite == 1'b0) ? exSignals.loadStoreRegTag : R0,
        storeValue          : (exSignals.readWrite == 1'b1) ? exSignals.loadStoreValue  : R0,
        aluResultRegTag     : (writeback)                   ? exSignals.baseRegTag      : R0,
        aluResultValue      : (writeback)                   ? aluResult                 : 32'h00000000,
        psrValue            : 8'h00,
        psrUpdated          : 1'b0
      };
    end else begin
      instrIsLoad           = 1'b0;
      instrSetsControlFlags = 1'b0;
      branchAddress         = 32'h00000000;
      branchEnable          = 1'b0;
      exception             = (psrValue.t) ? EXCEPT_SYSCALL: EXCEPT_NONE;
      resultRegTag          = loadStoreRegTag;
      memSignals = '{
        linkAddress         : exSignals.linkAddress,
        memoryAccess        : 1'b0,
        readWrite           : 1'b0,
        halfAccess          : 1'b0,
        byteAccess          : 1'b0,
        memoryAccessAddress : 32'h00000000,
        loadRegTag          : R0,
        storeValue          : 32'h00000000,
        aluResultRegTag     : loadStoreRegTag,
        aluResultValue      : aluResult,
        psrValue            : (exSignals.setPsrFlagsOnly) ? { exSignals.psrValue[7:4], aluResultFlags[3:0] } : 8'h00,
        psrUpdated          : exSignals.setPsrFlagsOnly
      };
    end
  end

endmodule
