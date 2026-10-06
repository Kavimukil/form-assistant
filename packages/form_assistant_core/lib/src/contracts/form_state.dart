import 'bridge_codec.dart';
import 'structural_contract.dart';
import 'form_value.dart';

enum FormLifecycle { active, completed, readOnly }

final class FormStateSnapshot with StructuralContract {
  final FormId formId;
  final Revision revision;
  final Map<FieldId, FormValue> values; // immutable
  final FieldId? activeFieldId;
  final FormLifecycle lifecycle;
  FormStateSnapshot({
    required this.formId,
    required this.revision,
    required Map<FieldId, FormValue> values,
    required this.lifecycle,
    this.activeFieldId,
  }) : values = Map.unmodifiable(values) {
    if (revision < 0) throw ArgumentError.value(revision, "revision");
  }
  @override
  Map<String, Object?> toJson() => FormStateSnapshotCodec.encode(this);
}

final class FormStateBridgeCapabilities with StructuralContract {
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
  @override
  Map<String, Object?> toJson() =>
      FormStateBridgeCapabilitiesCodec.encode(this);
}
