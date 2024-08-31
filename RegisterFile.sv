`default_nettype none

typedef struct packed {
  bit p; // privilege level
  bit s; // supervisor bank
  bit t; // trap
  bit i; // interrupt disable
  bit c; // carry
  bit v; // overflow
  bit n; // negative
  bit z; // zero
} StatusFlags;

module RegisterFile (
  clk, reset,
  readRegTag, readValue, readValid,
  psrValue,
  exFlags, setControlFlags,
  exception, exceptionLinkAddress,
  resultCommitRegTag, resultCommitValue, resultCommitEnable,
  autoIncCommitRegTag, autoIncCommitValue, autoIncCommitEnable,
  psrCommitValue, psrCommitEnable, privilegeLevel,
  disableInterrupts,
  supervisorLinkAddress, supervisorLinkEnable
);

  // ============================================================================
  // PORT DECLARATIONS
  // ============================================================================

  input  bit         clk;
  input  bit         reset;
  input  RegTag      readRegTag [ISA_MAX_OPR-1:0];
  output Word        readValue  [ISA_MAX_OPR-1:0];
  output Word        psrValue;
  input  StatusFlags exControlFlags;
  input  bit         setControlFlags;
  input  Exception   exception;
  input  Word        exceptionLinkAddress;
  input  RegTag      resultCommitRegTag;
  input  Word        resultCommitValue;
  input  RegTag      autoIncCommitRegTag;
  input  Word        autoIncCommitValue;
  input  StatusFlags psrCommitValue;
  input  bit         psrCommitEnable;
  output bit         privilegeLevel;
  output bit         disableInterrupts;
  output Word        supervisorLinkAddress;
  output bit         supervisorLinkEnable;


  // ============================================================================
  // REGISTER FILE
  // ============================================================================
  
  Word userBank [15:01];
  Word privBank [15:14];

  bit pFlag = 1'b1;
  bit sFlag = 1'b1;
  bit iFlag = 1'b1;

  // READ
  always_comb begin
    foreach (readRegTag[i]) begin
      if (readRegTag[i] == 0) begin
        readValue[i] = '0;
      end else if (readRegTag[i] >= $low(privBank) && sFlag == 1'b1) begin
        readValue[i] = privBank[readRegTag[i]].value;
      end else begin
        readValue[i] = userBank[readRegTag[i]].value;
      end
    end
  end

  // INVALIDATE AND COMMIT
  always_ff @(posedge clk) begin
    if (reset) begin
      foreach (userBank[i]) userBank[i] <= '{ valid: 1'b1, value: 32'h0 };
      foreach (privBank[i]) privBank[i] <= '{ valid: 1'b1, value: 32'h0 };
    end else begin
      foreach (userBank[i]) begin
        // commit result
        if (i == resultCommitRegTag[j] && resultCommitEnable[j]) begin
          if (i >= $low(privBank) && psrCommitValue.s == 1'b1) begin
            privBank[i] <= resultCommitValue[j];
          end else begin
            userBank[i] <= resultCommitValue[j];
          end
        // commit auto-increment writeback
        end else if (i == autoIncCommitRegTag[j] && autoIncCommitEnable[j]) begin
          if (i >= $low(privBank) && psrCommitValue.s == 1'b1) begin
            privBank[i] <= autoIncCommitValue[j];
          end else begin
            userBank[i] <= autoIncCommitValue[j];
          end
        end
      end
      if (exception != EXCEPT_NONE) begin
        privBank[LR] <= exceptionLinkAddress;
      end
    end
  end

  // ============================================================================
  // PROGRAM STATUS REGISTER
  // ============================================================================

  StatusFlags userStatus;
  StatusFlags privStatus;

  // READ
  always_comb begin
    var StatusFlags flags;
    if (pFlag == 1'b1 && sFlag == 1'b1) begin
       flags = '{
        p: 1'b1,
        s: 1'b1,
        t: 1'b0,
        i: iFlag,
        c: privStatus.c,
        v: privStatus.v,
        n: privStatus.n,
        z: privStatus.z
      };
    end else begin
      flags = '{
        p: pFlag,
        s: 1'b0,
        t: userStatus.t,
        i: iFlag,
        c: userStatus.c,
        v: userStatus.v,
        n: userStatus.n,
        z: userStatus.z
      };
    end
    psrValue = { 24'h0, flags };
  end

  // UPDATE FLAGS
  always_ff @(posedge clk) begin
    if (exception != EXCEPT_NONE) begin
      pFlag <= 1'b1;
      sFlag <= 1'b1;
      iFlag <= 1'b1;
      userStatus.t <= (exception == EXCEPT_SYSCALL) ? 1'b0 : userStatus.t;
    end else if (setControlFlags) begin
      pFlag <= exControlFlags.p;
      sFlag <= exControlFlags.s;
      iFlag <= exControlFlags.i;
    end
    if (psrCommitEnable) begin
      userStatus <= psrCommitValue;
    end
  end

  assign privilegeLevel = pFlag;

  assign supervisorLinkAddress = privBank[LR];
  assign supervisorLinkEnable  = setControlFlags & pFlag & ~exControlFlags.p;

endmodule
