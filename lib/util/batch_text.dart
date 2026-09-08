/// Text-buffer rules for the search box's batch toggle.
///
/// Single mode shows only the first line; the remaining lines are parked in
/// [hidden] and restored when batch mode is switched back on. Editing the
/// first line in single mode replaces the old first line, the rest survives.
class BatchText {
  const BatchText._();

  /// Batch -> single: returns (visible first line, hidden remainder).
  static (String, String) toSingle(String full) {
    final lines = full.split('\n');
    return (lines.first, lines.skip(1).join('\n'));
  }

  /// Single -> batch: merges the (possibly edited) visible line with the
  /// parked remainder.
  static String toBatch(String visible, String hidden) {
    final first = visible.split('\n').first;
    return hidden.isEmpty ? first : '$first\n$hidden';
  }

  /// Keywords to search for in the given mode.
  static List<String> keywords(String text, {required bool batch}) =>
      (batch ? text.split('\n') : [text.split('\n').first])
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

  static int hiddenCount(String hidden) =>
      hidden.isEmpty ? 0 : hidden.split('\n').where((l) => l.trim().isNotEmpty).length;
}
