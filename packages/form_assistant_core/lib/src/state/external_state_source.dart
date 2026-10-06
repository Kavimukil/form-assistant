import '../contracts/form_value.dart';

/// An immutable authoritative source snapshot, not a canonical wire contract.
/// [version] is a source-owned, monotonically increasing concurrency token.
/// Its scope and increments are independent of the bridge's semantic revision.
final class ExternalStoreSnapshot<TState> {
  final int version;
  final TState state;
  final OperationId? operationId;
  const ExternalStoreSnapshot(
      {required this.version, required this.state, this.operationId});
}

sealed class ExternalWriteResult<TState> {
  final ExternalStoreSnapshot<TState> snapshot;
  const ExternalWriteResult(this.snapshot);
}

/// The source actually committed; this snapshot is an authoritative receipt.
final class ExternalWriteCommitted<TState> extends ExternalWriteResult<TState> {
  const ExternalWriteCommitted(super.snapshot);
}

/// The source rejected the write before mutation because its version changed.
final class ExternalWriteConflict<TState> extends ExternalWriteResult<TState> {
  const ExternalWriteConflict(super.snapshot);
}

/// Integration-owned port. It makes no assumptions about the store technology.
///
/// Publish immutable snapshots in commit order. Each actual source transaction
/// advances version, including presentation-only/focus changes. Duplicate echoes
/// reuse their original version. All manual/external writes share this version
/// boundary. [compareAndApply] checks the expected source version atomically with
/// the authoritative commit, never on dispatch alone. A committed receipt and its
/// notification carry the same operationId/version/state. Source notifications
/// must be delivered before a receipt for a later source transaction; wrappers
/// around asynchronous stores must preserve this ordering. Failures throw;
/// dispatch/acceptance alone must never return ExternalWriteCommitted.
abstract interface class ExternalStateSource<TState, TMutation> {
  ExternalStoreSnapshot<TState> get snapshot;
  Stream<ExternalStoreSnapshot<TState>> get changes;
  bool get supportsAtomicBatch;
  Future<ExternalWriteResult<TState>> compareAndApply(
    List<TMutation> mutations, {
    required int expectedSourceVersion,
    required OperationId operationId,
    required bool atomic,
  });
}
