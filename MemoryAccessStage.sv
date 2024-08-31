`default_nettype none

typedef struct {
  bit         memoryAccess;
  bit         readWrite;
  bit         halfAccess;
  bit         byteAccess;
  Word        memoryAccessAddress;
  RegTag      loadRegTag;
  Word        storeValue;
  RegTag      aluResultRegTag;
  Word        aluResultValue;
  StatusFlags psrValue;
  bit         psrUpdated;
} MemSignals;

module MemoryAccessStage (
  memSignals,
  address,
  dataIn, dataOut,
  readWrite, columnStrobe,
  forwardResultRegTag, forwardResultValue, instrIsLoad,
  forwardAutoIncRegTag, forwardAutoIncValue,
  busFault, exception,
  wbSignals
);

  // ============================================================================
  // PORT DECLARATIONS
  // ============================================================================

  input  MemSignals  memSignals;
  output Word        address;
  input  Word        dataIn;
  output Word        dataOut;
  output bit         readWrite;
  output bit [3:0]   columnStrobe;
  output bit         instrIsLoad;
  output RegTag      forwardResultRegTag;
  output Word        forwardResultValue;
  output RegTag      forwardAutoIncRegTag;
  output Word        forwardAutoIncValue;
  output StatusFlags forwardPsrValue;
  output bit         forwardPsrValid;
  input  bit         busFault;
  output Exception   exception;
  output WbSignals   wbSignals;


  // ============================================================================
  // DATA ALIGNMENT BASED ON ACCESS TYPE AND ADDRESSS
  // ============================================================================

  bit misalignedAccess;
  bit [3:0] accessBytes;
  bit [1:0] accessShift;

  always_comb begin
    var bit [1:0] alignment = memSignals.memoryAccessAddress[1:0];
    case ({ memSignals.halfAccess, memSignals.byteAccess })
      2'b00: begin // word access
        misalignedAccess = (alignment != 2'b00);
        accessBytes      = 4'b1111;
        accessShift      = 2'h0;
      end
      2'b01: begin // half access
        misalignedAccess = (alignment[0] != 1'b0);
        accessBytes      = (alignment[1]) ? 4'b1100 : 4'b0011;
        accessShift      = (alignment[1]) ? 2'h2 : 2'h0;
      end
      2'b10: begin // byte access
        misalignedAccess = (memSignals.memoryAccessAddress % 4 != 0); // WORD ACCESS
        accessBytes      = 4'b0001 << alignment;
        accessShift      = alignment;
      end
      2'b11: begin // unreachable
        misalignedAccess = 1'b0;
        accessBytes      = 4'b0000;
        accessShift      = 2'b0;
        $fatal(1, "unreachable state");
      end
    endcase
  end

  assign instrIsLoad = memAccess & (readWrite == 1'b0);

  assign exception = (busFault)         ? EXCEPT_BUS_FAULT
                   : (misalignedAccess) ? EXCEPT_USAGE_FAULT
                   :                      EXCEPT_NONE;


  // ============================================================================
  // SIGNALS TO WRITEBACK STAGE
  // ============================================================================

  always_comb begin
    if (!memoryAccess) begin
      dataOut              = 32'h00000000;
      readWrite            = 1'b0;
      columnStrobe         = 4'b0000;
      forwardResultRegTag  = memSignals.aluResultRegTag;
      forwardResultValue   = memSignals.aluResultValue;
      forwardAutoIncRegTag = 4'h0;
      forwardAutoIncValue  = 32'h00000000;
      wbSignals = '{
        resultRegTag       : memSignals.aluResultRegTag,
        resultValue        : memSignals.aluResultValue,
        autoIncRegTag      : 4'h0,
        autoIncRegValue    : 32'h00000000,
        psrValue           : memSignals.psrValue,
        psrUpdated         : memSignals.psrUpdated
      };
    end else if (memSignals.readWrite == 1'b1) begin // write
      dataOut              = memSignals.storeValue << (8 * accessShift);
      readWrite            = 1'b1;
      columnStrobe         = (misalignedAccess) ? 4'b0000 : accessBytes; 
      forwardResultRegTag  = 4'h0;
      forwardResultValue   = 32'h00000000;
      forwardAutoIncRegTag = memSignals.aluResultRegTag;
      forwardAutoIncValue  = memSignals.aluResultValue;
      wbSignals = '{
        resultRegTag       : 4'h0,
        resultValue        : 32'h0000000,
        autoIncRegTag      : memSignals.aluResultRegTag,
        autoIncRegValue    : memSignals.aluResultValue,
        psrValue           : 8'h00,
        psrUpdated         : 1'b0
      };
    end else begin // read
      dataOut              = 32'h00000000;
      readWrite            = 1'b0;
      columnStrobe         = (misalignedAccess) ? 4'b0000 : accessBytes;
      forwardResultRegTag  = memSignals.loadRegTag;
      forwardResultValue   = 32'h00000000;
      forwardAutoIncRegTag = memSignals.aluResultRegTag;
      forwardAutoIncValue  = memSignals.aluResultValue;
      wbSignals = '{
        resultRegTag       : memSignals.loadRegTag,
        resultValue        : dataIn >> (8 * accessShift),
        autoIncRegTag      : memSignals.aluResultRegTag,
        autoIncRegValue    : memSignals.aluResultValue,
        psrValue           : 8'h00,
        psrUpdated         : 1'b0
      };
    end
  end

endmodule
