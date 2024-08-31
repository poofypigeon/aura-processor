`default_nettype none

`define ISA_WORD_SIZE   32 // number of bits in a data word
`define ISA_REGTAG_SIZE  4 // number of bits to specify an architectural register
// `define ISA_MAX_OPR      3 // most operand dependencies an instruction can have

typedef bit [ISA_WORD_SIZE-1:0] Word;

typedef enum {
  R0  = 4'h0,
  R1  = 4'h1,
  R2  = 4'h2,
  R3  = 4'h3,
  R4  = 4'h4,
  R5  = 4'h5,
  R6  = 4'h6,
  R7  = 4'h7,
  R8  = 4'h8,
  R9  = 4'h9,
  R10 = 4'hA,
  R11 = 4'hB,
  R12 = 4'hC,
  R13 = 4'hD,
  SP  = 4'hE,
  LR  = 4'hF
} RegTag;

typedef enum bit [4:0] {
  EXCEPT_NONE        = 5'h00,
  EXCEPT_RESET       = 5'h01,
  EXCEPT_BUS_FAULT   = 5'h02,
  EXCEPT_USAGE_FAULT = 5'h03,
  EXCEPT_SYSCALL     = 5'h04,
  EXCEPT_INSTRUCTION = 5'h05,
  EXCEPT_SYSTICK     = 5'h06,
  EXCEPT_RES0        = 5'h07,
  EXCEPT_RES1        = 5'h08,
  EXCEPT_RES2        = 5'h09,
  EXCEPT_RES3        = 5'h0A,
  EXCEPT_RES4        = 5'h0B,
  EXCEPT_RES5        = 5'h0C,
  EXCEPT_RES6        = 5'h0D,
  EXCEPT_RES7        = 5'h0E,
  EXCEPT_RES8        = 5'h0F,
  EXCEPT_IRQ0        = 5'h10,
  EXCEPT_IRQ1        = 5'h11,
  EXCEPT_IRQ2        = 5'h12,
  EXCEPT_IRQ3        = 5'h13,
  EXCEPT_IRQ4        = 5'h14,
  EXCEPT_IRQ5        = 5'h15,
  EXCEPT_IRQ6        = 5'h16,
  EXCEPT_IRQ7        = 5'h17
} Exception;

module Core (
  clk, reset,
    .privilegeLevel         (privilegeLevel),
    .ifVirtualAddressBus    (programCounter),
    .ifDataBus              (instruction),
    .ifStall                (ifStall),
    .ifBusFault             (ifBusFault),
    .memVirtualAddressBus   (memAddress),
    .memDataInBus           (memDataIn),
    .memDataOutBus          (memDataOut),
    .memReadWrite           (memReadWrite),
    .memColumnStrobe        (memColumnStrobe),
    .memStall               (memStall),
    .memBusFault            (memBusFault),
    .physicalAddressBus     (), // TODO ???
    .physicalDataBus        (),
    .physicalReadWrite      (),
    .physicalColumnStrobe   ()
);

  RegTag      regFileReadRegTag   [3:0];
  Word        regFileReadValue    [3:0];

  Word        memAddress;
  Word        memDataIn, memDataOut;
  bit         memReadWrite;
  bit [3:0]   memColumnStrobe;

  RegTag      memForwardResultRegTag;
  Word        memForwardResultValue;
  RegTag      memForwardAutoIncRegTag;
  Word        memForwardAutoIncValue;
  StatusFlags memForwardPsrValue;
  bit         memForwardPsrValid;

  RegTag      resultCommitRegTag;
  Word        resultCommitValue;
  RegTag      autoIncCommitRegTag;
  Word        autoIncCommitValue;
  StatusFlags psrCommitValue;
  bit         psrCommitEnable;

  alias wbForwardResultRegTag  = resultCommitRegTag;
  alias wbForwardResultValue   = resultCommitValue;
  alias wbForwardAutoIncRegTag = autoIncCommitRegTag;
  alias wbForwardAutoIncValue  = autoIncCommitValue;
  alias wbForwardPsrValue      = psrCommitValue;
  alias wbForwardPsrValid      = psrCommitEnable;





  bit branchEnable;
  Word branchAddress;

  Word programCounter;
  Word instruction;

  bit privilegeLevel;
  Word exControlFlags;





  // ============================================================================
  // STALL FOR DATA HAZARDS
  // ============================================================================

  bit       exInstrIsLoad, memInstrIsLoad;
  bit       exInstrSetsControlFlags;
  RegTag    exResultRegTag;

  bit       idStall, memStall;
  alias     exStall = memStall;
  alias     ifStall = idStall;

  always_comb begin
    var bit idDependsOnEx  = 1'b0;
    var bit idDependsOnMem = 1'b0;
    var bit idDependsOnWb  = 1'b0;

    foreach (regFileReadRegTag[i]) begin
      if (regFileReadRegTag[i] == exResultRegTag)         idDependsOnEx  = 1'b1;
      // hazard not present in case of regFileReadRegTag[i] == exAutoIncRegTag
      if (regFileReadRegTag[i] == memForwardResultRegTag) idDependsOnMem = 1'b1;
      // hazard not present in case of regFileReadRegTag[i] == memForwardAutoIncRegTag
      if (regFileReadRegTag[i] == wbForwardResultRegTag)  idDependsOnWb  = 1'b1;
      if (regFileReadRegTag[i] == wbForwardAutoIncRegTag) idDependsOnWb  = 1'b1;
    end

    idStall = exStall;

    // stall for possible bank switching data hazard
    if (privilegeLevel == 1'b1 && exInstrSetsControlFlags) idStall = 1'b1;

    // stall for load-use data hazards
    if (idDependsOnEx  && exInstrIsLoad)                   idStall = 1'b1;
    if (idDependsOnMem && idDependsOnWb && memInstrIsLoad) idStall = 1'b1;
  end


  // ============================================================================
  // BRANCH AND EXCEPTIONS
  // ============================================================================
 
  bit ifBusFault, memBusFault;

  Exception exException, memException;
  Exception exception;

  bit memFlush, exFlush, idFlush;

  Word exceptionLinkAddress;

  assign memFlush = (memException != EXCEPT_NONE);
  assign exFlush  = ( exException != EXCEPT_NONE) | memFlush;
  assign idFlush  = branchEnable                  | exFlush;
  alias  ifFlush  = idFlush;


  assign exception   = (memException != EXCEPT_NONE) ? memException : exException;
  assign jumpEnable  = ((exception != EXCEPT_NONE) || supervisorLinkEnable || branchEnable);

  assign jumpAddress = (exception != EXCEPT_NONE) ? exception
                     : (supervisorLinkEnable)     ? supervisorLinkAddress
                     :                              branchAddress;

  assign exceptionLinkAddress = (memBusFault) ? memSignals.programCounter : exSignals.programCounter;


  // TODO Pull out of module
  MemoryManagementUnit memoryManagementUnit (
    .privilegeLevel         (privilegeLevel),
    .ifVirtualAddressBus    (programCounter),
    .ifDataBus              (instruction),
    .ifStall                (ifStall),
    .ifBusFault             (ifBusFault),
    .memVirtualAddressBus   (memAddress),
    .memDataInBus           (memDataIn),
    .memDataOutBus          (memDataOut),
    .memReadWrite           (memReadWrite),
    .memColumnStrobe        (memColumnStrobe),
    .memStall               (memStall),
    .memBusFault            (memBusFault),
    .physicalAddressBus     (), // TODO ???
    .physicalDataBus        (),
    .physicalReadWrite      (),
    .physicalColumnStrobe   ()
  );

  RegisterFile registerFile (
    .clk                    (clk),
    .reset                  (reset),
    .readRegTag             (regFileReadRegTag),
    .readValue              (regFileReadValue),
    .psrValue               (psrValue),
    .exControlFlags         (exControlFlags),
    .setControlFlags        (exInstrSetsControlFlags),
    .exception              (exception),
    .exceptionLinkAddress   (exceptionLinkAddress),
    .resultCommitRegTag     (resultCommitRegTag),
    .resultCommitValue      (resultCommitValue),
    .AutoIncCommitRegTag    (autoIncCommitRegTag),
    .AutoIncCommitValue     (autoIncCommitValue),
    .psrCommitValue         (psrCommitValue),
    .psrCommitEnable        (psrCommitEnable),
    .disableInterrupts      (disableInterrupts),
    .privilegeLevel         (privilegeLevel),
    .supervisorLinkAddress  (supervisorLinkAddress),
    .supervisorLinkEnable   (supervisorLinkEnable)
  );


  // ============================================================================
  // INSTRUCTION FETCH STAGE
  // ============================================================================
  
  IdSignals ifToId;
  IdSignals idSignals;

  FetchStage fetchStage (
    .clk                    (clk),
    .reset                  (reset),
    .stall                  (ifStall),
    .jumpAddress            (jumpAddress),
    .jumpEnable             (jumpEnable),
    .busFault               (ifBusFault),
    .instruction            (instruction),
    .programCounter         (programCounter),
    .idSignals              (idSignals)
  );

  always_ff @(posedge clk) begin
    if      (reset | ifFlush) ifToId <= '{ default: 0 };
    else if (ifStall)         ifToId <= ifToId;
    else                      ifToId <= idSignals;
  end


  // ============================================================================
  // INSTRUCTION DECODE STAGE
  // ============================================================================

  ExSignals idToEx;
  ExSignals exSignals;

  DecodeStage decodeStage (
    .idSignals              (ifToId),
    // .stall                  (idStall),
    .regFileReadRegTag      (regFileReadRegTag),
    .regFileReadValue       (regFileReadValue),
    .regFilePsrValue        (psrValue),
    // .exResultRegTag         (exResultRegTag),
    .memforwardResultRegTag (memForwardResultRegTag),
    .memforwardResultValue  (memForwardResultValue),
    .memforwardAutoIncRegTag(memForwardAutoIncRegTag),
    .memforwardAutoIncValue (memForwardAutoIncValue),
    .memforwardPsrValue     (memForwardPsrValue),
    .memforwardPsrValid     (memForwardPsrValid),
    .wbforwardResultRegTag  (wbForwardResultRegTag),
    .wbforwardResultValue   (wbForwardResultValue),
    .wbforwardAutoIncRegTag (wbForwardAutoIncRegTag),
    .wbforwardAutoIncValue  (wbForwardAutoIncValue),
    .wbforwardPsrValue      (wbForwardPsrValue),
    .wbforwardPsrValid      (wbForwardPsrValid),
    .exSignals              (exSignals)
  );

  always_ff @(posedge clk) begin
    if      (reset | idFlush) idToEx <= '{ default: 0 };
    else if (idStall)         idToEx <= idToEx;
    else                      idToEx <= exSignals;
  end


  // ============================================================================
  // EXECUTE STAGE
  // ============================================================================

  MemSignals exToMem;
  MemSignals memSignals;

  ExecuteStage executeStage (
    .exSignals              (idToEx),
    // .exStall                (exStall),
    .instrIsLoad            (exInstrIsLoad),
    .instrSetsControlFlags  (exInstrSetsControlFlags),
    .branchAddress          (branchAddress),
    .branchEnable           (branchEnable),
    .exception              (exException),
    .resultRegTag           (exResultRegTag),
    .memforwardResultRegTag (memForwardResultRegTag),
    .memforwardResultValue  (memForwardResultValue),
    .memforwardAutoIncRegTag(memForwardAutoIncRegTag),
    .memforwardAutoIncValue (memForwardAutoIncValue),
    .memforwardPsrValue     (memForwardPsrValue),
    .memforwardPsrValid     (memForwardPsrValid),
    .wbforwardResultRegTag  (wbForwardResultRegTag),
    .wbforwardResultValue   (wbForwardResultValue),
    .wbforwardAutoIncRegTag (wbForwardAutoIncRegTag),
    .wbforwardAutoIncValue  (wbForwardAutoIncValue),
    .wbforwardPsrValue      (wbForwardPsrValue),
    .wbforwardPsrValid      (wbForwardPsrValid),
    .memSignals             (memSignals)
  );

  always_ff @(posedge clk) begin
    if      (reset | exFlush) exToMem <= '{ default: 0 };
    else if (exStall)         exToMem <= exToMem;
    else                      exToMem <= memSignals;
  end

  assign exControlFlags = memSignals.flags;


  // ============================================================================
  // MEMORY ACCESS STAGE
  // ============================================================================

  WbSignals memToWb;
  WbSignals wbSignals;

  MemoryAccessStage memoryAccessStage (
    .memSignals             (exToMem),
    .address                (memAdddress),
    .dataIn                 (memDataIn),
    .dataOut                (memDataOut),
    .readWrite              (memReadWrite),
    .columnStrobe           (memColumnStrobe),
    .instrIsLoad            (memInstrIsLoad),
    .forwardResultRegTag    (memForwardResultRegTag),
    .forwardResultValue     (memForwardResultValue),
    .forwardAutoIncRegTag   (memForwardAutoIncRegTag),
    .forwardAutoIncValue    (memForwardAutoIncValue),
    .forwardPsrValue        (memForwardPsrValue),
    .forwardPsrValid        (memForwardPsrValid),
    .busFault               (memBusFault),
    .exception              (memException),
    .wbSignals              (wbSignals)
  );

  always_ff @(posedge clk) begin
    if      (reset | memFlush) memToWb <= '{ default: 0 };
    else if (memStall)         memToWb <= memToWb;
    else                       memToWb <= wbSignals;
  end


  // ============================================================================
  // WRITEBACK STAGE
  // ============================================================================

  WritebackStage writebackStage (
    .wbSignals              (memToWb),
    .resultCommitRegTag     (resultCommitRegTag),
    .resultCommitValue      (resultCommitValue),
    .autoIncCommitRegTag    (autoIncCommitRegTag),
    .autoIncCommitValue     (autoIncCommitValue),
    .psrCommitValue         (psrCommitValue),
    .psrCommitEnable        (psrCommitEnable)
  );

endmodule
