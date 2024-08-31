`default_nettype none

typedef struct {
  Exception exception;
  Word instruction;
  Word programCounter;
  Word linkAddress;
} IdSignals;

module DecodeStage(
  idSignals,
  // stall,
  regFileReadRegTag, regFileReadValue,
  regFilePsrValue,
  // exResultRegTag,
  memforwardResultRegTag, memforwardResultValue,
  memforwardAutoIncRegTag, memforwardAutoIncValue,
  memforwardPsrValue,
  memforwardPsrValid,
  wbforwardResultRegTag,
  wbforwardResultValue,
  wbforwardAutoIncRegTag,
  wbforwardAutoIncValue,
  wbforwardPsrValue,
  wbforwardPsrValid,
  exSignals
);

  // ============================================================================
  // PORT DECLARATIONS
  // ============================================================================

  input  IdSignals idSignals;
  output RegTag    regFileReadRegTag;
  input  Word      regFileReadValue;
  input  RegTag    memforwardResultRegTag;
  input  Word      memforwardResultValue;
  input  RegTag    memforwardAutoIncRegTag;
  input  Word      memforwardAutoIncValue;
  input  Word      memforwardPsrValue;
  input  bit       memforwardPsrValid;
  input  RegTag    wbforwardResultRegTag;
  input  Word      wbforwardResultValue;
  input  RegTag    wbforwardAutoIncRegTag;
  input  Word      wbforwardAutoIncValue;
  input  Word      wbforwardPsrValue;
  input  bit       wbforwardPsrValid;
  output ExSignals exSignals;


  // ============================================================================
  // OPERAND FORWARDING
  // ============================================================================

  RegTag loadStoreRegTag;
  RegTag baseRegTag;
  RegTag offsetRegTag;
  RegTag shiftRegTag;

  assign loadStoreRegTag = idSignals.instruction[27:24];
  assign baseRegTag      = idSignals.instruction[23:20];
  assign offsetRegTag    = idSignals.instruction[03:00];
  assign shiftRegTag     = idSignals.instruction[13:10];

  Word      loadStoreValue;
  Word      baseValue;
  Word      offsetValue;
  bit [7:0] shiftValue;

  always_comb begin
    regFileReadRegTag[0] = loadStoreRegTag;
    if      (loadStoreRegTag == R0)                      loadStoreValue = 32'h00000000;
    else if (loadStoreRegTag == memForwardResultRegTag)  loadStoreValue = memForwardResultValue;
    else if (loadStoreRegTag == memForwardAutoIncRegTag) loadStoreValue = memForwardAutoIncValue;
    else if (loadStoreRegTag == wbForwardResultRegTag)   loadStoreValue = wbForwardResultValue;
    else if (loadStoreRegTag == wbForwardAutoIncRegTag)  loadStoreValue = wbForwardAutoIncValue;
    else                                                 loadStoreValue = regFileReadValue[0];

    regFileReadRegTag[1] = baseRegTag;
    if      (baseRegTag == R0)                           baseValue      = 32'h00000000;
    else if (baseRegTag == memForwardResultRegTag)       baseValue      = memForwardResultValue;
    else if (baseRegTag == memForwardAutoIncRegTag)      baseValue      = memForwardAutoIncValue;
    else if (baseRegTag == wbForwardResultRegTag)        baseValue      = wbForwardResultValue;
    else if (baseRegTag == wbForwardAutoIncRegTag)       baseValue      = wbForwardAutoIncValue;
    else                                                 baseValue      = regFileReadValue[1];

    regFileReadRegTag[2] = baseRegTag;
    if      (offsetRegTag == R0)                         offsetValue    = 32'h00000000;
    else if (offsetRegTag == memForwardResultRegTag)     offsetValue    = memForwardResultValue;
    else if (offsetRegTag == memForwardAutoIncRegTag)    offsetValue    = memForwardAutoIncValue;
    else if (offsetRegTag == wbForwardResultRegTag)      offsetValue    = wbForwardResultValue;
    else if (offsetRegTag == wbForwardAutoIncRegTag)     offsetValue    = wbForwardAutoIncValue;
    else                                                 offsetValue    = regFileReadValue[2];

    regFileReadRegTag[3] = baseRegTag;
    if      (shiftRegTag == R0)                          shiftValue     = 32'h00000000;
    else if (shiftRegTag == memForwardResultRegTag)      shiftValue     = memForwardResultValue;
    else if (shiftRegTag == memForwardAutoIncRegTag)     shiftValue     = memForwardAutoIncValue;
    else if (shiftRegTag == wbForwardResultRegTag)       shiftValue     = wbForwardResultValue;
    else if (shiftRegTag == wbForwardAutoIncRegTag)      shiftValue     = wbForwardAutoIncValue;
    else                                                 shiftValue     = regFileReadValue[3];

    if      (memForwardPsrValid && memForwardPsrValue.s == regFilePsrValue.s) psrValue = memForwardPsrValue;
    else if (wbForwardPsrValid  && wbForwardPsrValue.s  == regFilePsrValue.s) psrValue = wbForwardPsrValue;
    else                                                                      psrValue = regFilePsrValue;
  end

  
  // ============================================================================
  // SIGNALS TO EXECUTE STAGE
  // ============================================================================
  
  bit [3:0] opcode;
  assign opcode = idSignals.instruction[31:28];

  bit psrInstruction;
  assign psrInstruction = & idSignals.instruction[16:15];

  always_comb begin
    var bit usageFault = 1'b0;

    casez ({ opcode, psrInstruction })
      5'b00??0: begin // DATA TRANSFER INSTRUCTION
        var bit       sBit     = idSignals.instruction[29];
        var bit       pBit     = idSignals.instruction[19];
        var bit       dBit     = idSignals.instruction[18];
        var bit       wBit     = idSignals.instruction[17];
        var bit       hBit     = idSignals.instruction[16];
        var bit       bBit     = idSignals.instruction[15];
        var bit [7:0] shiftImm = { 3'h0, idSignals.instruction[14:10] };

        exSignals = '{
          exception       : EXCEPT_NONE,
          linkAddress     : idSignals.linkAddress,
          memoryAccess    : 1'b1,
          readWrite       : sBit,
          postIncOffset   : pBit,
          writebackOffset : wBit,
          halfAccess      : hBit,
          byteAccess      : bBit,
          getPsr          : 1'b0,
          setPsrFlagsOnly : 1'b0,
          setPsr          : 1'b0,
          shiftRight      : 1'b0,
          shiftArithmetic : 1'b0,
          branch          : 1'b0,
          link            : 1'b0,
          branchCondition : 4'h0, // TODO could use 4'hF in place of branch bit
          aluCode         : (dBit) ? ALU_SUB : ALU_ADD,
          loadStoreRegTag : loadStoreRegTag,
          loadStoreValue  : loadStoreValue,
          baseRegTag      : baseRegTag,
          baseValue       : baseValue,
          shiftRegTag     : R0,
          shiftValue      : shiftImm,
          offsetRegTag    : offsetRegTag,
          offsetValue     : offsetValue,
          psrValue        : psrValue
        };
      end
      5'b00001: begin // MOVE FROM PSR
        exSignals = '{
          exception       : EXCEPT_NONE,
          linkAddress     : idSignals.linkAddress,
          memoryAccess    : 1'b0,
          readWrite       : 1'b0,
          postIncOffset   : 1'b0,
          writebackOffset : 1'b0,
          halfAccess      : 1'b0,
          byteAccess      : 1'b0,
          getPsr          : 1'b1,
          setPsrFlagsOnly : 1'b0,
          setPsr          : 1'b0,
          shiftRight      : 1'b0,
          shiftArithmetic : 1'b0,
          branch          : 1'b0,
          link            : 1'b0,
          branchCondition : 4'h0,
          aluCode         : ALU_ADD,
          loadStoreRegTag : loadStoreRegTag,
          loadStoreValue  : 32'h00000000,
          baseRegTag      : R0,
          baseValue       : 32'h00000000,
          shiftRegTag     : R0,
          shiftValue      : 32'h00000000,
          offsetRegTag    : R0,
          offsetValue     : 32'h00000000,
          psrValue        : psrValue 
        };
      end
      5'b001?1: begin // MOVE TO PSR
        var bit  fBit = idSignals.instruction[17];
        var bit  iBit = idSignals.instruction[28];
        var Word imm  = { 22'h000000, idSignals.instruction[9:0] };

        if (!fBit && !psrValue.s) usageFault = 1'b1;

        exSignals = '{
          exception       : EXCEPT_NONE,
          linkAddress     : idSignals.linkAddress,
          memoryAccess    : 1'b0,
          readWrite       : 1'b0,
          postIncOffset   : 1'b0,
          writebackOffset : 1'b0,
          halfAccess      : 1'b0,
          byteAccess      : 1'b0,
          getPsr          : 1'b0,
          setPsrFlagsOnly : fBit,
          setPsr          : 1'b1,
          shiftRight      : 1'b0,
          shiftArithmetic : 1'b0,
          branch          : 1'b0,
          link            : 1'b0,
          branchCondition : 4'b0,
          aluCode         : ALU_ADD,
          loadStoreRegTag : R0,
          loadStoreValue  : 32'h00000000,
          baseRegTag      : R0,
          baseValue       : 32'h00000000,
          shiftRegTag     : R0,
          shiftValue      : 32'h00000000,
          offsetRegTag    : (iBit) ? R0  : offsetRegTag,
          offsetValue     : (iBit) ? imm : offsetValue,
          psrValue        : psrValue
        };
      end
      5'b01???: begin // DATA PROCESSING
        var bit       aBit     = idSignals.instruction[16];
        var bit       dBit     = idSignals.instruction[15];
        var bit       hBit     = idSignals.instruction[29];
        var bit       iBit     = idSignals.instruction[28];
        var AluCode   aluCode  = idSignals.instruction[19:17];
        var bit [7:0] shiftImm = { 3'h0, idSignals.instruction[14:10] };
        var Word      imm      = { { 22{idSignals.instruction[9]} }, idSignals.instruction[9:0] };

        exSignals = '{
          exception       : EXCEPT_NONE,
          linkAddress     : idSignals.linkAddress,
          memoryAccess    : 1'b0,
          readWrite       : 1'b0,
          postIncOffset   : 1'b0,
          writebackOffset : 1'b0,
          halfAccess      : 1'b0,
          byteAccess      : 1'b0,
          getPsr          : 1'b0,
          setPsrFlagsOnly : (!aBit || dBit),
          setPsr          : 1'b0,
          shiftRight      : dBit,
          shiftArithmetic : aBit
          branch          : 1'b0,
          link            : 1'b0,
          branchCondition : 4'h0,
          aluCode         : aluCode,
          loadStoreRegTag : loadStoreRegTag,
          loadStoreValue  : 32'h00000000,
          baseRegTag      : baseRegTag,
          baseValue       : baseValue,
          shiftRegTag     : (hBit) ? R0       : shiftRegTag,
          shiftValue      : (hBit) ? shiftImm : shiftValue,
          offsetRegTag    : (iBit) ? R0       : offsetRegTag,
          offsetValue     : (iBit) ? imm      : offsetValue,
          psrValue        : psrValue
        };
      end
      5'b10???: begin // BRANCH
        var bit       lBit            = idSignals.instruction[29];
        var bit       iBit            = idSignals.instruction[28];
        var bit [3:0] branchCondition = idSignals.instruction[27:24];
        var Word      imm             = { { 8{idSignals.instruction[23]} }, idSignals.instruction[23:0] };

        exSignals = '{
          exception       : EXCEPT_NONE,
          linkAddress     : idSignals.linkAddress,
          memoryAccess    : 1'b0,
          readWrite       : 1'b0,
          postIncOffset   : 1'b0,
          writebackOffset : 1'b0,
          halfAccess      : 1'b0,
          byteAccess      : 1'b0,
          getPsr          : 1'b0,
          setPsrFlagsOnly : 1'b0,
          setPsr          : 1'b0,
          shiftRight      : 1'b0,
          shiftArithmetic : 1'b0,
          branch          : 1'b1,
          link            : lBit,
          branchCondition : branchCondition,
          aluCode         : ALU_ADD,
          loadStoreRegTag : (lBit) ? LR : R0,
          loadStoreValue  : idSignals.linkAddress,
          baseRegTag      : R0,
          baseValue       : (iBit) ? idSignals.programCounter : 32'h00000000,
          shiftRegTag     : R0,
          shiftValue      : (iBit) ? 8'h02 : 8'h00,
          offsetRegTag    : (iBit) ? R0    : offsetRegTag,
          offsetValue     : (iBit) ? imm   : offsetValue,
          psrValue        : psrValue
        };
      end
      5'b110??: begin // MOVE IMMEDIATE
        var Word imm = { { 8{idSignals.instruction[28]} }, idSignals.instruction[23:0] };

        exSignals = '{
          exception       : EXCEPT_NONE,
          linkAddress     : idSignals.linkAddress,
          memoryAccess    : 1'b0,
          readWrite       : 1'b0,
          postIncOffset   : 1'b0,
          writebackOffset : 1'b0,
          halfAccess      : 1'b0,
          byteAccess      : 1'b0,
          getPsr          : 1'b0,
          setPsrFlagsOnly : 1'b0,
          setPsr          : 1'b0,
          shiftRight      : 1'b0,
          shiftArithmetic : 1'b0,
          branch          : 1'b0,
          link            : 1'b0,
          branchCondition : 4'h0,
          aluCode         : ALU_ADD,
          loadStoreRegTag : loadStoreRegTag,
          loadStoreValue  : 32'h00000000,
          baseRegTag      : R0,
          baseValue       : 32'h00000000,
          shiftRegTag     : R0,
          shiftValue      : 8'h00,
          offsetRegTag    : R0,
          offsetValue     : imm,
          psrValue        : psrValue
        };
      end
      5'b1110?: begin // INSTRUCTION SYSCALL
        exSignals = '{
          exception       : EXCEPT_INSTRUCTION,
          linkAddress     : idSignals.linkAddress,
          default         : 0
        };
      end
      5'b1111?: begin // SYSCALL
        exSignals = '{
          exception       : EXCEPT_SYSCALL,
          linkAddress     : idSignals.linkAddress,
          default         : 0
        };
      end
      default: usageFault = 1'b1;
    endcase

    if (idSignals.exception != EXCEPT_NONE) begin
      exSignals = '{
        exception       : idSignals.exception,
        linkAddress     : idSignals.linkAddress,
        default         : 0
      };
    end else if (usageFault) begin
      exSignals = '{
        exception       : EXCEPT_USAGE_FAULT,
        linkAddress     : idSignals.linkAddress,
        default         : 0
      };
    end
  end
