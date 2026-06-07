import '../../shared/errors/domain_exception.dart';

/// The flavor of reference a [SyncRef] holds.
enum RefKind {
  /// A 40- or 64-char git commit SHA.
  gitCommitSha,

  /// A hash over a directory's file manifest.
  directoryManifestHash;

  String get wireValue => name;

  static RefKind fromWire(String value) => values.firstWhere(
    (e) => e.wireValue == value,
    orElse: () => throw ValidationException('Unknown ref kind: $value'),
  );
}

/// The universal baseline reference used by the synchronization engine.
///
/// For git drives this is the commit SHA the local copy was materialized from;
/// for directory drives it is the hash of the downloaded file manifest. A push
/// is only allowed when the origin still points at the recorded baseline.
class SyncRef {
  final RefKind kind;
  final String value;

  SyncRef(this.kind, String value) : value = value.trim() {
    if (this.value.isEmpty) {
      throw const ValidationException('Sync ref value is required');
    }
  }

  /// Convenience constructor for a git commit SHA.
  factory SyncRef.git(String sha) => SyncRef(RefKind.gitCommitSha, sha);

  /// Convenience constructor for a directory manifest hash.
  factory SyncRef.directory(String hash) =>
      SyncRef(RefKind.directoryManifestHash, hash);

  Map<String, dynamic> toJson() => {'kind': kind.wireValue, 'value': value};

  factory SyncRef.fromJson(Map<String, dynamic> json) => SyncRef(
    RefKind.fromWire(json['kind'] as String),
    json['value'] as String,
  );

  @override
  bool operator ==(Object other) =>
      other is SyncRef && other.kind == kind && other.value == value;

  @override
  int get hashCode => Object.hash(kind, value);

  @override
  String toString() => '${kind.wireValue}:$value';
}
