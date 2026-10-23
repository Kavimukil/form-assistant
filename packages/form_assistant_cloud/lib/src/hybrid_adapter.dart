import 'dart:async';

import 'package:form_assistant_core/form_assistant_core.dart';

import 'capability.dart';
import 'cloud_adapter.dart';

/// One fallback decision. Trace ids match the interaction that requested it.
final class FallbackEvent {
  final TraceContext trace;
  final String reason;
  final String? localAdapterId;
  final String? cloudAdapterId;
  final String? localProposalId;
  final String? cloudProposalId;
  final bool cloudInvoked;
  final bool blocked;
  const FallbackEvent(
      {required this.trace,
      required this.reason,
      this.localAdapterId,
      this.cloudAdapterId,
      this.localProposalId,
      this.cloudProposalId,
      required this.cloudInvoked,
      required this.blocked});
}

/// Local adapter first. Cloud runs only after QualityGate returns fallback
/// and capability policy allows it. Sensitive context never reaches cloud.
final class HybridIntelligenceAdapter implements IntelligenceAdapter {
  final IntelligenceAdapter? local;
  final CloudLLMAdapter? cloud;
  final IntelligenceCapabilities Function() capabilities;
  final SensitiveContextPolicy sensitivity;
  final QualityGate qualityGate;
  @override
  final String id;
  @override
  final String version;
  final List<FallbackEvent> _events = [];
  List<FallbackEvent> get events => List.unmodifiable(_events);

  HybridIntelligenceAdapter(
      {this.local,
      this.cloud,
      required this.capabilities,
      SensitiveContextPolicy? sensitivity,
      QualityGate? qualityGate,
      this.id = 'hybrid',
      this.version = '0.1.0'})
      : sensitivity = sensitivity ?? SensitiveContextPolicy(),
        qualityGate = qualityGate ?? QualityGate();

  @override
  Future<IntelligenceResult> interpret(IntelligenceRequest request,
      {IntelligenceOptions? options}) {
    final settings = options ?? const IntelligenceOptions();
    return runIntelligence(() => _interpret(request, settings), settings);
  }

  Future<IntelligenceResult> _interpret(
      IntelligenceRequest request, IntelligenceOptions options) async {
    final caps = capabilities();
    final sensitive = sensitivity.prohibitsCloud(request.context);
    final allowCloud = caps.cloudTransportPermitted && !sensitive;
    if (caps.localModelAvailable && local != null) {
      try {
        final result = await local!.interpret(request, options: options);
        final decision = qualityGate.considerFallback(
            QualityDecision(result.quality ?? QualityOutcome.accept,
                result.qualityReason ?? 'validated', result.proposal.actions),
            allowFallback: allowCloud);
        if (decision.outcome != QualityOutcome.fallback) {
          return _adopt(request, result, local!.id);
        }
        return _fallback(request, options,
            reason: decision.reason,
            allowCloud: allowCloud,
            sensitive: sensitive,
            localAdapterId: local!.id,
            localProposalId: result.proposal.id);
      } on IntelligenceCancelled {
        rethrow;
      } on TimeoutException {
        rethrow;
      } catch (error) {
        return _fallback(request, options,
            reason: 'local_failed',
            allowCloud: allowCloud,
            sensitive: sensitive,
            localAdapterId: local!.id,
            detail: '$error');
      }
    }
    return _fallback(request, options,
        reason: 'local_unavailable',
        allowCloud: allowCloud,
        sensitive: sensitive,
        localAdapterId: local?.id);
  }

  Future<IntelligenceResult> _fallback(
      IntelligenceRequest request, IntelligenceOptions options,
      {required String reason,
      required bool allowCloud,
      required bool sensitive,
      String? localAdapterId,
      String? localProposalId,
      String? detail}) async {
    if (!allowCloud || cloud == null) {
      final blockedReason =
          sensitive ? 'sensitive_context' : 'cloud_unavailable';
      _events.add(FallbackEvent(
          trace: request.trace,
          reason: blockedReason,
          localAdapterId: localAdapterId,
          localProposalId: localProposalId,
          cloudInvoked: false,
          blocked: true));
      return _clarify(request, blockedReason, detail: detail ?? reason);
    }
    final result = await cloud!.interpret(request, options: options);
    _events.add(FallbackEvent(
        trace: request.trace,
        reason: reason,
        localAdapterId: localAdapterId,
        cloudAdapterId: cloud!.id,
        localProposalId: localProposalId,
        cloudProposalId: result.proposal.id,
        cloudInvoked: true,
        blocked: false));
    return _adopt(request, result, cloud!.id);
  }

  IntelligenceResult _adopt(IntelligenceRequest request,
      IntelligenceResult result, String backendId) {
    final proposal = result.proposal;
    return IntelligenceResult(
        proposal: ActionProposal(
            id: proposal.id,
            baseRevision: proposal.baseRevision,
            actions: proposal.actions,
            confidence: proposal.confidence,
            provenance: ActionProvenance(
                trace: _trace(request, proposal.id),
                adapterId: id,
                adapterVersion: version,
                backendId: backendId)),
        quality: result.quality,
        qualityReason: result.qualityReason);
  }

  IntelligenceResult _clarify(IntelligenceRequest request, String reason,
      {String? detail}) {
    final proposalId = '${request.trace.requestId}/hybrid-blocked';
    return IntelligenceResult(
        proposal: ActionProposal(
            id: proposalId,
            baseRevision: request.context.revision,
            actions: [
              ProposedAction(
                  id: '$proposalId/action/0',
                  action: RequestClarificationAction(
                      reason: reason == 'sensitive_context'
                          ? ClarificationReason.invalidValue
                          : ClarificationReason.missingInformation,
                      detail: detail ?? reason))
            ],
            provenance: ActionProvenance(
                trace: _trace(request, proposalId),
                adapterId: id,
                adapterVersion: version)),
        quality: QualityOutcome.clarify,
        qualityReason: reason);
  }

  TraceContext _trace(IntelligenceRequest request, String proposalId) =>
      TraceContext(
          interactionId: request.trace.interactionId,
          requestId: request.trace.requestId,
          operationId: request.trace.operationId,
          proposalId: proposalId,
          segmentId: request.trace.segmentId);
}
