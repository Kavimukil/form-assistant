import 'package:form_assistant_core/form_assistant_core.dart';

/// Host-owned reachability. The adapters never probe the network themselves.
final class IntelligenceCapabilities {
  final bool networkAvailable;
  final bool cloudAllowed;
  final bool localModelAvailable;
  const IntelligenceCapabilities(
      {required this.networkAvailable,
      required this.cloudAllowed,
      required this.localModelAvailable});

  bool get cloudTransportPermitted => networkAvailable && cloudAllowed;
}

/// Field ids and concepts that must not leave the device.
final class SensitiveContextPolicy {
  final Set<String> fieldIds;
  final Set<String> concepts;
  SensitiveContextPolicy(
      {Iterable<String> fieldIds = const [],
      Iterable<String> concepts = const []})
      : fieldIds = Set.unmodifiable(fieldIds),
        concepts = Set.unmodifiable(concepts);

  bool prohibitsCloud(SemanticContext context) => context.fields.any((field) =>
      fieldIds.contains(field.id) ||
      (field.concept != null && concepts.contains(field.concept)));
}
