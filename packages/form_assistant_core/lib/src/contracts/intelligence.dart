import 'dart:async';
import 'dart:convert';

import 'canonical_json.dart';
import 'form_ir.dart';
import 'form_state_bridge.dart';
import 'form_value.dart';
import 'trace.dart';
import 'validation_metadata.dart';

/// Text boundary passed to the router and model. Voice audio and transcript
/// confidence stay outside this type.
final class UserInput {
  final String text;
  final SegmentId? segmentId;
  const UserInput({required this.text, this.segmentId});
}

enum SemanticValueType {
  string,
  integer,
  number,
  boolean,
  date,
  choice,
  multiChoice
}

enum FieldSelectionReason {
  active,
  candidate,
  dependency,
  reference,
  recent,
  unanswered
}

/// Compatibility wrapper: canonical field access remains available to runtime.
final class FormFieldContext {
  final FormField field;
  final FormValue? currentValue;
  final bool writable;
  final bool optionsTruncated;
  final Set<FieldSelectionReason> selectionReasons;
  const FormFieldContext(
      {required this.field,
      this.currentValue,
      this.writable = true,
      this.optionsTruncated = false,
      this.selectionReasons = const {}});
  String get id => field.id;
  String get label => field.semantics.label;
  String? get concept => field.semantics.concept;
  List<String> get aliases => field.semantics.aliases;
  FieldConstraints? get constraints => field.constraints;
  List<FormOption> get options => field.options ?? const [];
  SemanticValueType get type => switch (field.value) {
        StringDefinition() => SemanticValueType.string,
        IntegerDefinition() => SemanticValueType.integer,
        NumberDefinition() => SemanticValueType.number,
        BooleanDefinition() => SemanticValueType.boolean,
        DateDefinition() => SemanticValueType.date,
        ChoiceDefinition(:final multiple) =>
          multiple ? SemanticValueType.multiChoice : SemanticValueType.choice,
      };
  Map<String, Object?> toJson() => {
        'id': id,
        'type':
            type == SemanticValueType.multiChoice ? 'multi_choice' : type.name,
        'label': label,
        if (concept != null) 'concept': concept,
        'aliases': aliases,
        if (field.semantics.localizedLabels.isNotEmpty)
          'localizedLabels': field.semantics.localizedLabels,
        if (field.semantics.localizedAliases.isNotEmpty)
          'localizedAliases': {
            for (final entry in field.semantics.localizedAliases.entries)
              entry.key: entry.value,
          },
        'currentValue': currentValue?.toJson(),
        'writable': writable,
        'optionsTruncated': optionsTruncated,
        if (constraints != null) 'constraints': constraints!.toJson(),
        'options': [
          for (final option in options)
            {
              'id': option.id,
              'label': option.label,
              'aliases': option.aliases,
              if (option.localizedLabels.isNotEmpty)
                'localizedLabels': option.localizedLabels,
              if (option.localizedAliases.isNotEmpty)
                'localizedAliases': {
                  for (final entry in option.localizedAliases.entries)
                    entry.key: entry.value,
                },
            }
        ],
      };
  factory FormFieldContext.fromJson(Object? input) {
    final j = jsonObject(input);
    final kind = requiredString(j, 'type');
    final definition = kind == 'multi_choice' || kind == 'choice'
        ? ChoiceDefinition(multiple: kind == 'multi_choice')
        : ValueDefinition.fromJson({'type': kind});
    return FormFieldContext(
        field: FormField(
            id: requiredId(j, 'id'),
            value: definition,
            semantics: FieldSemantics.fromJson({
              'label': requiredString(j, 'label'),
              if (j.containsKey('concept')) 'concept': j['concept'],
              if (j.containsKey('aliases')) 'aliases': j['aliases'],
              if (j.containsKey('localizedLabels'))
                'localizedLabels': j['localizedLabels'],
              if (j.containsKey('localizedAliases'))
                'localizedAliases': j['localizedAliases'],
            }),
            constraints: j.containsKey('constraints')
                ? FieldConstraints.fromJson(j['constraints'])
                : null,
            options: requireType<List<Object?>>(j['options'])
                .map(FormOption.fromJson)
                .toList()),
        currentValue: j['currentValue'] == null
            ? null
            : FormValueCodec.decode(j['currentValue']),
        writable: requireType<bool>(j['writable']),
        optionsTruncated: requireType<bool>(j['optionsTruncated']));
  }
}

typedef SemanticFieldContext = FormFieldContext;

/// Canonical sorted JSON identity. No probabilistic hash collisions and no
/// dependency in core; not an authentication token. Cache compares exact bytes.
String semanticFingerprint(Object? value) {
  Object? canonical(Object? v) {
    if (v is Map<String, Object?>) {
      final keys = v.keys.toList()..sort();
      return {for (final key in keys) key: canonical(v[key])};
    }
    if (v is List<Object?>) return v.map(canonical).toList();
    return v;
  }

  return 'canonical-json:' + jsonEncode(canonical(freezeJson(value)));
}

String normalizeSemanticLocale(String locale) =>
    locale.trim().replaceAll('_', '-').toLowerCase();

final class InteractionHistoryEntry {
  final String interactionId;
  final String text;
  final List<FieldId> fieldIds;
  InteractionHistoryEntry(
      {required this.interactionId,
      required this.text,
      List<FieldId> fieldIds = const []})
      : fieldIds = List.unmodifiable(fieldIds);
}

final class SemanticContext {
  static const currentSpecVersion = '1.1';
  final String specVersion;
  final FormId formId;
  final Revision revision;
  final FieldId? activeFieldId;
  final List<FormFieldContext> fields;
  final Map<FieldId, FormValue> values;
  final String locale;
  final List<InteractionHistoryEntry> history;
  final List<String> recentFieldIds;
  late final String fingerprint = semanticFingerprint(modelRelevantJson());
  SemanticContext(
      {this.specVersion = currentSpecVersion,
      required this.formId,
      required this.revision,
      this.activeFieldId,
      required List<FormFieldContext> fields,
      Map<FieldId, FormValue> values = const {},
      String locale = 'en',
      List<InteractionHistoryEntry> history = const [],
      List<String> recentFieldIds = const []})
      : locale = normalizeSemanticLocale(locale),
        fields = List.unmodifiable(fields.map((f) => FormFieldContext(
            field: f.field,
            currentValue: values[f.id] ?? f.currentValue,
            writable: f.writable,
            optionsTruncated: f.optionsTruncated,
            selectionReasons: Set.unmodifiable(f.selectionReasons)))),
        values = Map.unmodifiable({
          for (final f in fields)
            if (values[f.id] != null || f.currentValue != null)
              f.id: values[f.id] ?? f.currentValue!
        }),
        history = List.unmodifiable(history),
        recentFieldIds = List.unmodifiable(recentFieldIds) {
    if (specVersion != currentSpecVersion ||
        revision < 0 ||
        formId.isEmpty ||
        this.locale.isEmpty ||
        fields.map((f) => f.id).toSet().length != fields.length ||
        fields.any((f) => f.id.isEmpty)) {
      throw ArgumentError('Invalid SemanticContext v1.1');
    }
    final ids = fields.map((f) => f.id).toSet();
    if (activeFieldId != null &&
            !ids.contains(activeFieldId) &&
            fields.isNotEmpty ||
        recentFieldIds.any((id) => !ids.contains(id))) {
      throw ArgumentError('Unknown context reference');
    }
  }
  Map<String, Object?> modelRelevantJson() => {
        'locale': locale,
        'activeFieldId': activeFieldId,
        'recentFieldIds': recentFieldIds,
        'fields': fields.map((f) => f.toJson()).toList(),
      };
  Map<String, Object?> toJson() => {
        'specVersion': specVersion,
        'formId': formId,
        'revision': revision,
        'fingerprint': fingerprint,
        ...modelRelevantJson()
      };
  factory SemanticContext.fromJson(Object? input) {
    final j = jsonObject(input);
    if (j['specVersion'] != currentSpecVersion) {
      throw const FormatException(
          'Explicit v1.1 required; legacy constructor is compatibility path');
    }
    final result = SemanticContext(
        formId: requiredId(j, 'formId'),
        revision: requireType<int>(j['revision']),
        locale: requiredString(j, 'locale'),
        activeFieldId: optional<String>(j, 'activeFieldId'),
        recentFieldIds: stringList(j['recentFieldIds']),
        fields: requireType<List<Object?>>(j['fields'])
            .map(FormFieldContext.fromJson)
            .toList());
    if (j['fingerprint'] != result.fingerprint) {
      throw const FormatException('Semantic fingerprint mismatch');
    }
    return result;
  }
}

final class IntelligenceRequest {
  final UserInput input;
  final SemanticContext context;
  final List<String> allowedActionTypes;
  final TraceContext trace;
  IntelligenceRequest(
      {required this.input,
      required this.context,
      required Iterable<String> allowedActionTypes,
      required this.trace})
      : allowedActionTypes = canonicalStrings(allowedActionTypes);
}

/// Cooperative cancellation shared by runtime and inference adapters.
final class CancellationToken {
  bool _cancelled = false;
  final Set<void Function()> _listeners = {};
  bool get isCancelled => _cancelled;
  void throwIfCancelled() {
    if (_cancelled) throw const IntelligenceCancelled();
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    final listeners = List.of(_listeners);
    _listeners.clear();
    for (final listener in listeners) {
      listener();
    }
  }

  void Function() listen(void Function() listener) {
    if (_cancelled) {
      listener();
      return () {};
    }
    _listeners.add(listener);
    return () {
      _listeners.remove(listener);
    };
  }
}

final class IntelligenceCancelled implements Exception {
  const IntelligenceCancelled();
}

final class IntelligenceOptions {
  final Duration timeout;
  final CancellationToken? cancellation;
  const IntelligenceOptions(
      {this.timeout = const Duration(seconds: 30), this.cancellation});
}

/// Applies timeout/cancellation even to adapters without physical abort support.
/// Late completions are observed but never returned to the caller.
Future<T> runIntelligence<T>(
    Future<T> Function() work, IntelligenceOptions options) async {
  if (options.timeout <= Duration.zero) {
    throw ArgumentError('Invalid inference timeout');
  }
  options.cancellation?.throwIfCancelled();
  final result = Completer<T>();
  final detach = options.cancellation?.listen(() {
    if (!result.isCompleted) {
      result.completeError(const IntelligenceCancelled());
    }
  });
  final timer = Timer(options.timeout, () {
    if (!result.isCompleted) {
      result.completeError(
          TimeoutException('Intelligence timeout', options.timeout));
    }
  });
  try {
    Future<T>.sync(work).then((value) {
      if (!result.isCompleted) result.complete(value);
    }, onError: (Object error, StackTrace stack) {
      if (!result.isCompleted) result.completeError(error, stack);
    });
    return await result.future;
  } finally {
    timer.cancel();
    detach?.call();
  }
}

final class ActionProvenance {
  final TraceContext trace;
  final String adapterId;
  final String adapterVersion;
  final ActionOrigin origin;

  /// Which composed backend produced the proposal. Outside canonical actions.
  final String? backendId;
  const ActionProvenance(
      {required this.trace,
      required this.adapterId,
      required this.adapterVersion,
      this.origin = ActionOrigin.intelligence,
      this.backendId});
}

final class ActionProposal {
  final ProposalId id;
  final Revision baseRevision;
  final List<ProposedAction> actions;
  final ActionProvenance provenance;
  final double? confidence;
  ActionProposal(
      {required this.id,
      required this.baseRevision,
      required List<ProposedAction> actions,
      required this.provenance,
      this.confidence})
      : actions = List.unmodifiable(actions) {
    if (baseRevision < 0 ||
        (confidence != null &&
            (!confidence!.isFinite || confidence! < 0 || confidence! > 1))) {
      throw ArgumentError('Invalid proposal revision/confidence');
    }
    if (id.isEmpty ||
        actions.any((a) => a.id.isEmpty) ||
        actions.map((a) => a.id).toSet().length != actions.length) {
      throw ArgumentError('Proposal/action IDs must be nonempty and unique');
    }
  }
}

enum QualityOutcome { accept, clarify, fallback }

final class IntelligenceResult {
  final ActionProposal proposal;
  final QualityOutcome? quality;
  final String? qualityReason;
  const IntelligenceResult(
      {required this.proposal, this.quality, this.qualityReason});
}

abstract interface class IntelligenceAdapter {
  String get id;
  String get version;
  Future<IntelligenceResult> interpret(IntelligenceRequest request,
      {IntelligenceOptions? options});
}

/// The only intelligence implementation in Phase 3: caller-scripted results.
final class MockIntelligenceAdapter implements IntelligenceAdapter {
  @override
  final String id;
  @override
  final String version;
  final FutureOr<IntelligenceResult> Function(IntelligenceRequest request)
      handler;
  final List<IntelligenceRequest> _requests = [];
  List<IntelligenceRequest> get requests => List.unmodifiable(_requests);
  MockIntelligenceAdapter(
      {required this.handler, this.id = 'mock', this.version = '0.1.0'});
  @override
  Future<IntelligenceResult> interpret(IntelligenceRequest request,
      {IntelligenceOptions? options}) async {
    return runIntelligence(() async {
      _requests.add(request);
      return await handler(request);
    }, options ?? const IntelligenceOptions());
  }
}
