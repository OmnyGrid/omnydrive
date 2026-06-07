import '../../shared/errors/domain_exception.dart';

/// The reason a synchronization conflict was raised.
enum ConflictKind {
  /// The source reference moved away from the synchronized baseline.
  refMoved,

  /// Both the local copy and the origin changed the same content.
  contentDivergence,

  /// A push targeted a protected branch (e.g. `main`).
  protectedBranch,

  /// A path that was modified locally was deleted at the source.
  deletedAtSource;

  String get wireValue => name;

  static ConflictKind fromWire(String value) => values.firstWhere(
    (e) => e.wireValue == value,
    orElse: () => throw ValidationException('Unknown conflict kind: $value'),
  );
}
