import 'dart:convert';

import '../contracts/context_configuration.dart';
import '../contracts/form_ir.dart';
import '../contracts/form_state.dart';
import '../contracts/form_value.dart';
import '../contracts/intelligence.dart';

/// Internal retrieval strategy; never exported from the package barrel.
final class ContextCompiler {
  final FormIR form;
  final ContextBudget budget;
  final Map<String, List<String>> dependencies;
  late final Map<String, FormField> _fields = {
    for (final f in form.fields) f.id: f
  };
  ContextCompiler(
      {required this.form,
      required this.budget,
      Map<String, List<String>> dependencies = const {}})
      : dependencies = Map.unmodifiable({
          for (final e in dependencies.entries)
            e.key: List<String>.unmodifiable(e.value)
        }) {
    for (final e in this.dependencies.entries) {
      if (!_fields.containsKey(e.key) ||
          e.value.any((id) => !_fields.containsKey(id))) {
        throw ArgumentError('Unknown canonical dependency field');
      }
    }
  }

  CompiledContext compile(
      {required FormStateSnapshot snapshot,
      required UserInput input,
      List<String> candidates = const [],
      List<String> explicitDependencies = const [],
      List<String> recent = const [],
      List<InteractionHistoryEntry> history = const []}) {
    final reasons = <String, String>{};
    final mandatory = <String>{};
    void add(String id, String reason, {bool required = false}) {
      if (!_fields.containsKey(id)) {
        throw ArgumentError('Unknown context field: $id');
      }
      reasons.putIfAbsent(id, () => reason);
      if (required) mandatory.add(id);
    }

    final active = snapshot.activeFieldId;
    if (active != null) add(active, 'active', required: true);
    for (final id in candidates.toSet().toList()..sort()) {
      add(id, 'candidate');
    }
    for (final id in explicitDependencies.toSet().toList()..sort()) {
      add(id, 'dependency', required: true);
    }
    // Exact canonical labels/aliases in the utterance retrieve candidates only;
    // interpretation and action selection remain behind the router/adapter.
    final utterance = ' ${_words(input.text)} ';
    for (final field in form.fields) {
      if ([field.id, field.semantics.label, ...field.semantics.aliases]
          .any((name) {
        final words = _words(name);
        return words.isNotEmpty && utterance.contains(' $words ');
      })) {
        add(field.id, 'reference');
      }
    }
    if (RegExp(r'\b(previous|last)\s+(answer|field)\b', caseSensitive: false)
        .hasMatch(input.text)) {
      final previous = history.reversed
          .expand((h) => h.fieldIds)
          .where((id) => id != active)
          .firstOrNull;
      if (previous != null) add(previous, 'previous_reference');
    }
    // Transitive rule hints, canonical IDs only. Cycles terminate via seen set.
    final queue = reasons.keys.toList();
    final seen = <String>{};
    for (var i = 0; i < queue.length; i++) {
      final id = queue[i];
      if (!seen.add(id)) continue;
      for (final dep in (dependencies[id] ?? const <String>[]).toList()
        ..sort()) {
        add(dep, 'dependency', required: true);
        queue.add(dep);
      }
    }
    for (final id in recent.take(budget.maxRecentFields)) {
      add(id, 'recent_changed');
    }
    for (final field in form.fields) {
      if (!snapshot.values.containsKey(field.id)) add(field.id, 'unanswered');
    }
    // Active/dependencies must fit; candidates/reference/history/context are
    // optional. Stable canonical ID ties; recency preserves newest-first order.
    final ordered = [
      ...mandatory,
      ...reasons.keys.where((id) => !mandatory.contains(id))
    ];
    final selected = <FormFieldContext>[];
    final values = <String, FormValue>{};
    final selectedReasons = <String, String>{};
    final omitted = <String, String>{};
    final keptHistory = <InteractionHistoryEntry>[];
    SemanticContext context() => SemanticContext(
        formId: form.id,
        revision: snapshot.revision,
        activeFieldId: active,
        fields: selected,
        values: values,
        history: keptHistory,
        recentFieldIds: recent
            .take(budget.maxRecentFields)
            .where((id) => selected.any((f) => f.id == id))
            .toList());
    bool fits(SemanticContext candidate) {
      final chars = contextChars(candidate);
      return chars <= budget.maxChars &&
          (chars + 3) ~/ 4 <= budget.maxEstimatedTokens;
    }

    if (!fits(context())) throw const ContextBudgetExceeded();
    for (final id in ordered) {
      if (selected.length >= budget.maxFields) {
        if (mandatory.contains(id)) throw const ContextBudgetExceeded();
        omitted[id] = 'field_budget';
        continue;
      }
      final source = _fields[id]!;
      final textChars = [
        source.semantics.label,
        source.semantics.description ?? '',
        source.semantics.concept ?? '',
        ...source.semantics.aliases.take(budget.maxAliasesPerField)
      ].join().length;
      if (textChars > budget.maxFieldCharacters) {
        if (mandatory.contains(id)) throw const ContextBudgetExceeded();
        omitted[id] = 'field_character_budget';
        continue;
      }

      selected.add(FormFieldContext(
          field: _semanticField(source, budget),
          writable: snapshot.lifecycle == FormLifecycle.active,
          optionsTruncated:
              (source.options?.length ?? 0) > budget.maxOptionsPerField));
      if (snapshot.values.containsKey(id)) values[id] = snapshot.values[id]!;
      if (!fits(context())) {
        selected.removeLast();
        values.remove(id);
        if (mandatory.contains(id)) throw const ContextBudgetExceeded();
        omitted[id] = 'size_budget';
        continue;
      }
      selectedReasons[id] = reasons[id]!;
    }
    for (final entry in history.reversed.take(budget.maxHistoryEntries)) {
      // History references only fields in the current compact context.
      final bounded = InteractionHistoryEntry(
          interactionId: entry.interactionId,
          text: String.fromCharCodes(
              entry.text.runes.take(budget.maxHistoryEntryChars)),
          fieldIds: entry.fieldIds.where(selectedReasons.containsKey).toList());
      keptHistory.insert(0, bounded);
      if (!fits(context())) {
        keptHistory.removeAt(0);
        break;
      }
    }
    final result = context();
    final chars = contextChars(result);
    return CompiledContext(
        result,
        ContextDiagnostics(
            selectedReasons: selectedReasons,
            omittedReasons: omitted,
            chars: chars,
            estimatedTokens: (chars + 3) ~/ 4,
            historyEntries: keptHistory.length));
  }
}

String _words(String text) =>
    text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
FormField _semanticField(FormField f, ContextBudget budget) => FormField(
    id: f.id,
    value: f.value,
    semantics: FieldSemantics(
        label: f.semantics.label,
        description: f.semantics.description,
        concept: f.semantics.concept,
        aliases: f.semantics.aliases.take(budget.maxAliasesPerField).toList()),
    constraints: f.constraints,
    options: f.options
        ?.take(budget.maxOptionsPerField)
        .map((o) => FormOption(
            id: o.id,
            label: o.label,
            aliases: o.aliases.take(budget.maxAliasesPerField).toList()))
        .toList());

/// Cost includes JSON escapes, canonical values/options, locale and history.
int contextChars(SemanticContext c) => jsonEncode({
      'formId': c.formId,
      'revision': c.revision,
      if (c.activeFieldId != null) 'activeFieldId': c.activeFieldId,
      'fields': c.fields
          .map((f) => {
                ...f.field.toJson(),
                'writable': f.writable,
                'optionsTruncated': f.optionsTruncated
              })
          .toList(),
      'values': c.values.map((id, value) => MapEntry(id, value.toJson())),
      'locale': c.locale,
      'history': c.history
          .map((h) => {
                'interactionId': h.interactionId,
                'text': h.text,
                'fieldIds': h.fieldIds
              })
          .toList()
    }).length;

final class CompiledContext {
  final SemanticContext context;
  final ContextDiagnostics diagnostics;
  const CompiledContext(this.context, this.diagnostics);
}

final class ContextBudgetExceeded implements Exception {
  const ContextBudgetExceeded();
}
