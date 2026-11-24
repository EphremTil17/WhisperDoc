/// Why the chosen OpenRouter model can't be used.
enum ModelSelectionProblem {
  none,

  /// No model chosen yet (the list hasn't loaded since the switch).
  notChosen,

  /// OpenRouter no longer serves it.
  retired,

  /// Zero data retention is on and no host of it qualifies any more.
  retainsData,
}
