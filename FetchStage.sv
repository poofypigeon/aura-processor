`default_nettype none

module FetchStage (
  clk, reset,
  stall,
  instruction,
  programCounter,
  jumpAddress, jumpEnable,
  busFault,
  idSignals
);

  // ============================================================================
  // PORT DECLARATIONS
  // ============================================================================

  input  bit       clk;
  input  bit       reset;
  input  bit       stall;
  input  Word      jumpAddress;
  input  bit       jumpEnable;
  input  bit       busFault;

  output Word      programCounter;
  output IdSignals idSignals;

  initial programCounter = 32'h0;


  // ============================================================================
  // UPDATE PROGRAM COUNTER
  // ============================================================================
  
  bit misalignedAddress;
  bit jump;

  assign misalignedAddress = (jumpAddress[1:0] != 2'b00);
  assign jump              = (jumpEnable && !misalignedAddress);

  Word nextContiguousAddress;
  assign nextContiguousAddress = programCounter + 4;

  always_ff @(posedge clk) begin
    if      (reset) programCounter <= 32'h0;
    else if (stall) programCounter <= programCounter;
    else if (jump)  programCounter <= jumpAddress;
    else            programCounter <= nextContiguousAddress;
  end


  // ============================================================================
  // SIGNALS TO INSTRUCTION DECODE STAGE
  // ============================================================================

  Exception exception;

  assign exception = (busFault)                        ? EXCEPT_BUS_FAULT
                   : (jumpEnable && misalignedAddress) ? EXCEPT_USAGE_FAULT
                   :                                     EXCEPT_NONE;

  assign idSignals = '{
    exception      : exception,
    instruction    : instruction,
    programCounter : programCounter,
    linkAddress    : nextContiguousAddress
  };

endmodule
