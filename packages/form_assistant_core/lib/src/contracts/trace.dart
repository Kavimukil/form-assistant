import 'canonical_json.dart';
import 'form_value.dart';
import 'structural_contract.dart';

typedef RequestId = String;
typedef SegmentId = String;

/// Provenance travels outside canonical actions and values.
final class TraceContext with StructuralContract {
  final InteractionId interactionId;
  final RequestId requestId;
  final OperationId operationId;
  final ProposalId? proposalId;
  final String? actionId;
  final SegmentId? segmentId;
  const TraceContext(
      {required this.interactionId,
      required this.requestId,
      required this.operationId,
      this.proposalId,
      this.actionId,
      this.segmentId});
  TraceContext withProposal(ProposalId id, {String? actionId}) => TraceContext(
      interactionId: interactionId,
      requestId: requestId,
      operationId: operationId,
      proposalId: id,
      actionId: actionId,
      segmentId: segmentId);
  TraceContext retry(int attempt) => TraceContext(
      interactionId: interactionId,
      requestId: '$requestId/reinterpret/$attempt',
      operationId: '$operationId/reinterpret/$attempt',
      segmentId: segmentId);
  @override
  Map<String, Object?> toJson() => {
        'specVersion': protocolSpecVersion,
        'interactionId': interactionId,
        'requestId': requestId,
        'operationId': operationId,
        if (proposalId != null) 'proposalId': proposalId,
        if (actionId != null) 'actionId': actionId,
        if (segmentId != null) 'segmentId': segmentId
      };
}
