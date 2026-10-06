/// Hard limits on the complete compiled semantic context JSON, including values
/// and history. Tokens are estimated as ceil(chars / 4), not measured with a model tokenizer.
final class ContextBudget {
  final int maxFields;
  final int maxChars;
  final int maxEstimatedTokens;
  final int maxHistoryEntries;
  final int maxHistoryEntryChars;
  final int maxRecentFields;
  final int maxAliasesPerField;
  final int maxOptionsPerField;
  final int maxFieldCharacters;
  ContextBudget(
      {this.maxFields = 16,
      this.maxChars = 12000,
      this.maxEstimatedTokens = 768,
      this.maxHistoryEntries = 4,
      this.maxHistoryEntryChars = 512,
      this.maxRecentFields = 5,
      this.maxAliasesPerField = 6,
      this.maxOptionsPerField = 32,
      this.maxFieldCharacters = 512}) {
    if (maxFields < 1 ||
        maxChars < 1 ||
        maxEstimatedTokens < 1 ||
        maxHistoryEntries < 0 ||
        maxHistoryEntryChars < 0 ||
        maxRecentFields < 0 ||
        maxAliasesPerField < 0 ||
        maxOptionsPerField < 0 ||
        maxFieldCharacters < 1) {
      throw ArgumentError('Invalid context budget');
    }
  }
}

/// Evaluation diagnostics contain canonical IDs and sizes, never answer values.
final class ContextDiagnostics {
  final Map<String, String> selectedReasons;
  final Map<String, String> omittedReasons;
  final int chars;
  final int estimatedTokens;
  final int historyEntries;
  ContextDiagnostics(
      {required Map<String, String> selectedReasons,
      required Map<String, String> omittedReasons,
      required this.chars,
      required this.estimatedTokens,
      required this.historyEntries})
      : selectedReasons = Map.unmodifiable(selectedReasons),
        omittedReasons = Map.unmodifiable(omittedReasons);
}
