`default_nettype none

typedef struct {
  RegTag      resultRegTag;
  Word        resultValue;
  RegTag      autoIncRegTag;
  Word        autoIncValue;
  StatusFlags psrValue;
  bit         psrUpdated;
} WbSignals;

module WritebackStage (
  wbSignals,
  resultCommitRegTag, resultCommitValue,
  autoIncCommitRegTag, autoIncCommitValue,
  psrCommitValue, psrCommitEnable
);

  // ============================================================================
  // PORT DECLARATIONS
  // ============================================================================

  input  WbSignals   wbSignals;
  output RegTag      resultCommitTag;
  output Word        resultCommitValue;
  output RegTag      autoIncCommitTag;
  output Word        autoIncCommitValue;
  output StatusFlags psrCommitValue;
  output bit         psrCommitEnable;


  // ============================================================================
  // ASSIGNMENTS
  // ============================================================================

  assign resultCommitRegTag  = wbSignals.resultRegTag;
  assign resultCommitValue   = wbSignals.resultValue;
  assign autoIncCommitRegTag = wbSignals.autoIncRegTag;
  assign autoIncCommitValue  = wbSignals.autoIncValue;
  assign psrCommitValue      = wbSignals.psrValue;
  assign psrCommitEnable     = wbSignals.psrUpdated;

endmodule
