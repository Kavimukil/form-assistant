# 03 — Public Contracts

This document is normative for V1. Code may be split across files, but semantics must not change.

## Canonical JSON rules

- portable JSON only: null, bool, string, finite number, array, object;
- strict decoding; no `"4"` -> `4` coercion;
- explicit `type` discriminators;
- omit optional null properties;
- unordered semantic collections are deduplicated and sorted;
- typed structural equality is authoritative; never compare `jsonEncode(a)`;
- source-system encodings never escape adapters;
- model-specific formats never become canonical formats.

## FormValue

```dart
typedef FormId = String;
typedef FieldId = String;
typedef Revision = int;
typedef InteractionId = String;
typedef ProposalId = String;
typedef OperationId = String;

abstract interface class CanonicalSerializable {
  Map<String, Object?> toJson();
}

enum FormValueKind {
  string,
  integer,
  number,
  boolean,
  date,
  choice,
  multiChoice,
}

sealed class FormValue implements CanonicalSerializable {
  const FormValue();
  FormValueKind get kind;
  Object get rawValue;
}

final class StringValue extends FormValue {
  final String value;
  const StringValue(this.value);
  @override FormValueKind get kind => FormValueKind.string;
  @override String get rawValue => value;
  @override Map<String,Object?> toJson() => {'type':'string','value':value};
  @override bool operator ==(Object o) => identical(this,o) || o is StringValue && o.value == value;
  @override int get hashCode => Object.hash(kind,value);
}

final class IntegerValue extends FormValue {
  final int value;
  const IntegerValue(this.value);
  @override FormValueKind get kind => FormValueKind.integer;
  @override int get rawValue => value;
  @override Map<String,Object?> toJson() => {'type':'integer','value':value};
  @override bool operator ==(Object o) => identical(this,o) || o is IntegerValue && o.value == value;
  @override int get hashCode => Object.hash(kind,value);
}

final class NumberValue extends FormValue {
  final double value;
  NumberValue(this.value) {
    if (!value.isFinite) throw ArgumentError.value(value, 'value', 'must be finite');
  }
  @override FormValueKind get kind => FormValueKind.number;
  @override double get rawValue => value;
  @override Map<String,Object?> toJson() => {'type':'number','value':value};
  @override bool operator ==(Object o) => identical(this,o) || o is NumberValue && o.value == value;
  @override int get hashCode => Object.hash(kind,value);
}

final class BooleanValue extends FormValue {
  final bool value;
  const BooleanValue(this.value);
  @override FormValueKind get kind => FormValueKind.boolean;
  @override bool get rawValue => value;
  @override Map<String,Object?> toJson() => {'type':'boolean','value':value};
  @override bool operator ==(Object o) => identical(this,o) || o is BooleanValue && o.value == value;
  @override int get hashCode => Object.hash(kind,value);
}

final class DateValue extends FormValue {
  /// Strict YYYY-MM-DD calendar date. Not DateTime/timestamp.
  final String value;
  DateValue(this.value); // implementation MUST strictly validate a real ISO calendar date
  @override FormValueKind get kind => FormValueKind.date;
  @override String get rawValue => value;
  @override Map<String,Object?> toJson() => {'type':'date','value':value};
  @override bool operator ==(Object o) => identical(this,o) || o is DateValue && o.value == value;
  @override int get hashCode => Object.hash(kind,value);
}

final class ChoiceValue extends FormValue {
  final String optionId;
  ChoiceValue(this.optionId) {
    if (optionId.isEmpty) throw ArgumentError.value(optionId,'optionId');
  }
  @override FormValueKind get kind => FormValueKind.choice;
  @override String get rawValue => optionId;
  @override Map<String,Object?> toJson() => {'type':'choice','value':optionId};
  @override bool operator ==(Object o) => identical(this,o) || o is ChoiceValue && o.optionId == optionId;
  @override int get hashCode => Object.hash(kind,optionId);
}

final class MultiChoiceValue extends FormValue {
  final List<String> optionIds;
  MultiChoiceValue(Iterable<String> values)
      : optionIds = List.unmodifiable((values.toSet().toList()..sort()));
  @override FormValueKind get kind => FormValueKind.multiChoice;
  @override List<String> get rawValue => optionIds;
  @override Map<String,Object?> toJson() => {'type':'multi_choice','value':optionIds};
  @override bool operator ==(Object o) =>
      identical(this,o) || o is MultiChoiceValue && _listEquals(optionIds,o.optionIds);
  @override int get hashCode => Object.hashAll([kind,...optionIds]);
}
```

Rules:
- unanswered = field absent from values map; no `NullValue`;
- IntegerValue(4) != NumberValue(4.0);
- multi-choice is an unordered semantic set in V1;
- choice stores canonical option ID, not display label/source option key;
- do not normalize StringValue implicitly;
- do not add ObjectValue/ListValue in V1.

## FormAction

```dart
enum ActionClassification { mutation, navigation, assistantControl, privileged }

sealed class FormAction implements CanonicalSerializable {
  const FormAction();
  String get type;
  ActionClassification get classification;
}

sealed class FormMutationAction extends FormAction {
  const FormMutationAction();
  FieldId get fieldId;
  @override ActionClassification get classification => ActionClassification.mutation;
}

final class SetValueAction extends FormMutationAction {
  @override final FieldId fieldId;
  final FormValue value;
  const SetValueAction({required this.fieldId, required this.value});
  @override String get type => 'set_value';
  @override Map<String,Object?> toJson() =>
      {'type':type,'fieldId':fieldId,'value':value.toJson()};
  @override bool operator ==(Object o) =>
      identical(this,o) || o is SetValueAction && o.fieldId == fieldId && o.value == value;
  @override int get hashCode => Object.hash(type,fieldId,value);
}

final class ClearValueAction extends FormMutationAction {
  @override final FieldId fieldId;
  const ClearValueAction({required this.fieldId});
  @override String get type => 'clear_value';
  @override Map<String,Object?> toJson() => {'type':type,'fieldId':fieldId};
  @override bool operator ==(Object o) =>
      identical(this,o) || o is ClearValueAction && o.fieldId == fieldId;
  @override int get hashCode => Object.hash(type,fieldId);
}

sealed class FormNavigationAction extends FormAction {
  const FormNavigationAction();
  @override ActionClassification get classification => ActionClassification.navigation;
}

sealed class NavigationTarget implements CanonicalSerializable {
  const NavigationTarget();
  String get type;
}

final class FieldNavigationTarget extends NavigationTarget {
  final FieldId fieldId;
  const FieldNavigationTarget({required this.fieldId});
  @override String get type => 'field';
  @override Map<String,Object?> toJson() => {'type':type,'fieldId':fieldId};
  @override bool operator ==(Object o) => o is FieldNavigationTarget && o.fieldId == fieldId;
  @override int get hashCode => Object.hash(type,fieldId);
}

final class NextNavigationTarget extends NavigationTarget {
  const NextNavigationTarget();
  @override String get type => 'next';
  @override Map<String,Object?> toJson() => {'type':type};
  @override bool operator ==(Object o) => o is NextNavigationTarget;
  @override int get hashCode => type.hashCode;
}

final class PreviousNavigationTarget extends NavigationTarget {
  const PreviousNavigationTarget();
  @override String get type => 'previous';
  @override Map<String,Object?> toJson() => {'type':type};
  @override bool operator ==(Object o) => o is PreviousNavigationTarget;
  @override int get hashCode => type.hashCode;
}

final class NavigateAction extends FormNavigationAction {
  final NavigationTarget target;
  const NavigateAction({required this.target});
  @override String get type => 'navigate';
  @override Map<String,Object?> toJson() => {'type':type,'target':target.toJson()};
  @override bool operator ==(Object o) => o is NavigateAction && o.target == target;
  @override int get hashCode => Object.hash(type,target);
}

sealed class AssistantControlAction extends FormAction {
  const AssistantControlAction();
  @override ActionClassification get classification => ActionClassification.assistantControl;
}

enum ClarificationReason { ambiguous, missingInformation, invalidValue, lowConfidence }

final class RequestClarificationAction extends AssistantControlAction {
  final List<FieldId> fieldIds; // MUST be deduplicated + sorted
  final ClarificationReason reason;
  final String? detail;
  RequestClarificationAction({
    Iterable<FieldId> fieldIds = const [],
    required this.reason,
    this.detail,
  }) : fieldIds = List.unmodifiable((fieldIds.toSet().toList()..sort()));

  @override String get type => 'request_clarification';
  @override Map<String,Object?> toJson() => {
    'type': type,
    if (fieldIds.isNotEmpty) 'fieldIds': fieldIds,
    'reason': switch(reason) {
      ClarificationReason.ambiguous => 'ambiguous',
      ClarificationReason.missingInformation => 'missing_information',
      ClarificationReason.invalidValue => 'invalid_value',
      ClarificationReason.lowConfidence => 'low_confidence',
    },
    if (detail != null) 'detail': detail,
  };
  // implementation MUST provide structural equality/hashCode.
}
```

Action identity/provenance does not belong inside FormAction.

## Validation envelope

```dart
enum ValidationStatus { notValidated, valid, invalid }
enum ValidationSeverity { info, warning, error }

final class ValidationIssue implements CanonicalSerializable {
  final String code;
  final ValidationSeverity severity;
  final FieldId? fieldId;
  final String? message; // diagnostic, not localized UI contract
  final Map<String,Object?> metadata; // recursively JSON-safe only
  const ValidationIssue({
    required this.code,
    required this.severity,
    this.fieldId,
    this.message,
    this.metadata = const {},
  });
  // toJson + structural equality required
}

final class ActionValidationMetadata implements CanonicalSerializable {
  final ValidationStatus status;
  final List<ValidationIssue> issues;
  final Revision? validatedAgainstRevision;
  const ActionValidationMetadata({
    required this.status,
    this.issues = const [],
    this.validatedAgainstRevision,
  });
  // toJson + structural equality required
}

final class ProposedAction {
  final String id;
  final FormAction action;
  final ActionValidationMetadata? validation;
  const ProposedAction({required this.id, required this.action, this.validation});
}
```

Use stable machine-readable issue codes such as:
`value.type_mismatch`, `value.above_maximum`, `value.option_unknown`,
`rule.field_hidden`, `policy.read_only`.

## FormStateBridge

```dart
enum FormLifecycle { active, completed, readOnly }

final class FormStateSnapshot {
  final FormId formId;
  final Revision revision;
  final Map<FieldId,FormValue> values; // immutable
  final FieldId? activeFieldId;
  final FormLifecycle lifecycle;
  const FormStateSnapshot({
    required this.formId,
    required this.revision,
    required this.values,
    required this.lifecycle,
    this.activeFieldId,
  });
}

final class FormStateBridgeCapabilities {
  final bool writable;
  final bool supportsBatch;
  final bool supportsAtomicBatch;
  final bool supportsUndo;
  final bool supportsRedo;
  final bool supportsExternalChanges;
  final bool supportsActiveField;
  final bool supportsNavigation;
  const FormStateBridgeCapabilities({
    required this.writable,
    required this.supportsBatch,
    required this.supportsAtomicBatch,
    required this.supportsUndo,
    required this.supportsRedo,
    required this.supportsExternalChanges,
    required this.supportsActiveField,
    required this.supportsNavigation,
  });
}

enum ActionOrigin { user, deterministic, intelligence, system, undo, redo }

final class ApplyContext {
  final Revision expectedRevision;
  final InteractionId interactionId;
  final OperationId operationId;
  final ProposalId? proposalId;
  final ActionOrigin origin;
  const ApplyContext({
    required this.expectedRevision,
    required this.interactionId,
    required this.operationId,
    required this.origin,
    this.proposalId,
  });
}

abstract interface class FormStateBridge {
  String get id;
  String get version;
  FormStateBridgeCapabilities get capabilities;
  FormStateSnapshot get snapshot;
  Stream<FormStateBridgeEvent> get events;

  Future<ActionResult> apply(FormAction action, {required ApplyContext context});

  Future<BatchActionResult> applyBatch(
    List<FormAction> actions, {
    required ApplyContext context,
    BatchApplyMode mode = BatchApplyMode.bestEffort,
  });

  Future<ActionResult> undo({required ApplyContext context});
  Future<ActionResult> redo({required ApplyContext context});
  Future<void> dispose();
}
```

## Action results

```dart
sealed class ActionResult {
  final FormAction action;
  const ActionResult({required this.action});
}

final class ActionApplied extends ActionResult {
  final Revision previousRevision;
  final Revision revision;
  final FormStateSnapshot snapshot;
  const ActionApplied({
    required super.action,
    required this.previousRevision,
    required this.revision,
    required this.snapshot,
  });
}

enum NoOpReason { valueUnchanged, alreadyClear, alreadyAtTarget }

final class ActionNoOp extends ActionResult {
  final Revision revision;
  final FormStateSnapshot snapshot;
  final NoOpReason reason;
  const ActionNoOp({
    required super.action,
    required this.revision,
    required this.snapshot,
    required this.reason,
  });
}

enum ActionRejectionCode {
  staleRevision,
  readOnly,
  unknownField,
  invalidValue,
  validationFailed,
  unsupportedAction,
  capabilityUnavailable,
  conflict,
  atomicBatchAborted,
  disposed,
  internalError,
}

final class ActionRejection {
  final ActionRejectionCode code;
  final String? message;
  final Map<String,Object?> details;
  const ActionRejection({required this.code, this.message, this.details = const {}});
}

final class ActionRejected extends ActionResult {
  final ActionRejection rejection;
  final FormStateSnapshot snapshot;
  const ActionRejected({
    required super.action,
    required this.rejection,
    required this.snapshot,
  });
}
```

Expected business conditions are results, not exceptions.

## Batch

```dart
enum BatchApplyMode { atomic, bestEffort }
enum BatchStatus { applied, partiallyApplied, noOp, rejected }

enum BatchRejectionCode {
  staleRevision,
  batchUnsupported,
  atomicBatchUnsupported,
  readOnly,
  conflict,
  disposed,
  internalError,
}

final class BatchRejection {
  final BatchRejectionCode code;
  final String? message;
  final Map<String,Object?> details;
  const BatchRejection({required this.code, this.message, this.details = const {}});
}

final class BatchActionResult {
  final BatchApplyMode mode;
  final Revision baseRevision;
  final Revision finalRevision;
  final BatchStatus status;
  final List<ActionResult> results;
  final FormStateSnapshot snapshot;
  final BatchRejection? rejection;
  const BatchActionResult({
    required this.mode,
    required this.baseRevision,
    required this.finalRevision,
    required this.status,
    required this.results,
    required this.snapshot,
    this.rejection,
  });
}
```

Atomic batch:
- revision check before processing;
- unsupported atomic => reject, never downgrade;
- validate all first;
- all commit or none;
- one revision increment;
- every ActionApplied references same previous/final revision.

Best effort:
- stale starting revision rejects entire batch before processing;
- actions may independently succeed/fail;
- successful commits may increment individually;
- bridge serializes the logical batch relative to its own writes.

## Bridge events

```dart
sealed class FormStateBridgeEvent {
  final String bridgeId;
  final DateTime timestamp;
  const FormStateBridgeEvent({required this.bridgeId, required this.timestamp});
}

final class BridgeInitialized extends FormStateBridgeEvent {
  final FormStateSnapshot snapshot;
  const BridgeInitialized({
    required super.bridgeId,
    required super.timestamp,
    required this.snapshot,
  });
}

enum ChangeOrigin { user, deterministic, intelligence, external, system, undo, redo }
enum FieldChangeType { set, changed, cleared }

final class FieldChange {
  final FieldId fieldId;
  final FormValue? previousValue;
  final FormValue? value;
  final FieldChangeType type;
  const FieldChange({
    required this.fieldId,
    required this.previousValue,
    required this.value,
    required this.type,
  });
}

final class StateChanged extends FormStateBridgeEvent {
  final Revision previousRevision;
  final Revision revision;
  final List<FieldChange> changes;
  final ChangeOrigin origin;
  final InteractionId? interactionId;
  final OperationId? operationId;
  final ProposalId? proposalId;
  const StateChanged({
    required super.bridgeId,
    required super.timestamp,
    required this.previousRevision,
    required this.revision,
    required this.changes,
    required this.origin,
    this.interactionId,
    this.operationId,
    this.proposalId,
  });
}

final class ActiveFieldChanged extends FormStateBridgeEvent {
  final FieldId? previousFieldId;
  final FieldId? fieldId;
  final ChangeOrigin origin;
  final InteractionId? interactionId;
  final OperationId? operationId;
  const ActiveFieldChanged({
    required super.bridgeId,
    required super.timestamp,
    required this.previousFieldId,
    required this.fieldId,
    required this.origin,
    this.interactionId,
    this.operationId,
  });
}

final class ActionCompleted extends FormStateBridgeEvent {
  final OperationId operationId;
  final InteractionId interactionId;
  final ProposalId? proposalId;
  final ActionResult result;
  const ActionCompleted({
    required super.bridgeId,
    required super.timestamp,
    required this.operationId,
    required this.interactionId,
    this.proposalId,
    required this.result,
  });
}

final class BatchCompleted extends FormStateBridgeEvent {
  final OperationId operationId;
  final InteractionId interactionId;
  final ProposalId? proposalId;
  final BatchActionResult result;
  const BatchCompleted({
    required super.bridgeId,
    required super.timestamp,
    required this.operationId,
    required this.interactionId,
    this.proposalId,
    required this.result,
  });
}

enum BridgeErrorCode {
  initializationFailed,
  externalStoreFailure,
  mappingFailure,
  serializationFailure,
  unexpectedState,
  operationFailure,
  disposed,
  unknown,
}

final class BridgeError extends FormStateBridgeEvent {
  final BridgeErrorCode code;
  final String message;
  final bool recoverable;
  final Object? cause; // runtime-only; never serialize
  final InteractionId? interactionId;
  final OperationId? operationId;
  const BridgeError({
    required super.bridgeId,
    required super.timestamp,
    required this.code,
    required this.message,
    required this.recoverable,
    this.cause,
    this.interactionId,
    this.operationId,
  });
}

final class BridgeDisposed extends FormStateBridgeEvent {
  const BridgeDisposed({required super.bridgeId, required super.timestamp});
}
```

Events are emitted in commit order. Commit/publish snapshot before emitting state event.
No StateChanged for no-op.
External mutations produce StateChanged(origin: external).
Do not duplicate UndoApplied/RedoApplied event classes.

## FormIR minimum V1

```dart
final class FormIR {
  final String specVersion; // "1.0"
  final FormId id;
  final List<FormField> fields;
  final List<String> requiredCapabilities;
  final Map<String,Object?> extensions;
}

final class FormField {
  final FieldId id;
  final ValueDefinition value;
  final FieldSemantics semantics;
  final FieldConstraints? constraints;
  final List<FormOption>? options;
  final Map<String,Object?> extensions;
}

sealed class ValueDefinition {}
final class StringDefinition extends ValueDefinition {}
final class IntegerDefinition extends ValueDefinition {}
final class NumberDefinition extends ValueDefinition {}
final class BooleanDefinition extends ValueDefinition {}
final class DateDefinition extends ValueDefinition {}
final class ChoiceDefinition extends ValueDefinition {
  final bool multiple;
}

final class FieldSemantics {
  final String label;
  final String? description;
  final String? concept;
  final List<String> aliases;
}

final class FieldConstraints {
  final bool required;
  final num? min;
  final num? max;
  final int? minLength;
  final int? maxLength;
  final String? pattern;
}

final class FormOption {
  final String id;
  final String label;
  final List<String> aliases;
  final Map<String,Object?> extensions;
}
```

Do not add repeating groups/objects/files/signatures until required.

## FormAdapter

```dart
abstract interface class FormAdapter<TSchema> {
  String get id;
  String get version;
  Future<FormIR> compile(TSchema schema);
}
```

Source-schema knowledge ends here.

## Intelligence

```dart
abstract interface class IntelligenceAdapter {
  String get id;
  String get version;
  Future<IntelligenceResult> interpret(
    IntelligenceRequest request, {
    IntelligenceOptions? options,
  });
}

final class IntelligenceRequest {
  final UserInput input;
  final SemanticContext context;
  final List<String> allowedActionTypes;
}

final class SemanticContext {
  final FormId formId;
  final Revision revision;
  final FieldId? activeFieldId;
  final List<FormFieldContext> fields;
  final Map<FieldId,FormValue> values;
  final String locale;
}

final class ActionProposal {
  final ProposalId id;
  final Revision baseRevision;
  final List<ProposedAction> actions;
  final ActionProvenance provenance;
  final double? confidence;
}
```

FunctionGemma, Needle, Cloud, Hybrid and Mock all implement the same adapter contract.
ContextCompiler is internal.

## STT

```dart
abstract interface class STTAdapter {
  String get id;
  String get version;
  STTCapabilities get capabilities;
  Future<STTSession> createSession(STTSessionConfig config);
}

abstract interface class STTSession {
  Future<void> pushAudio(AudioChunk chunk);
  Future<void> finish();
  Future<void> cancel();
  Stream<STTEvent> get events;
}
```

V1 audio boundary: PCM16 with explicit sample rate/channels.
STT events: partial, final, error, end.
Partial never commits state.
