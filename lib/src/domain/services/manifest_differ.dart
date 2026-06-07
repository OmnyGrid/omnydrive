import '../entities/file_manifest.dart';

/// The set of path-level changes between two [FileManifest]s.
class ManifestDiff {
  /// Paths present in the target but not the base.
  final List<String> added;

  /// Paths present in both but with different content.
  final List<String> modified;

  /// Paths present in the base but not the target.
  final List<String> removed;

  const ManifestDiff({
    this.added = const [],
    this.modified = const [],
    this.removed = const [],
  });

  bool get isEmpty => added.isEmpty && modified.isEmpty && removed.isEmpty;

  /// All changed paths, sorted.
  List<String> get allPaths => [...added, ...modified, ...removed]..sort();
}

/// Pure diffing of two directory manifests. No I/O.
class ManifestDiffer {
  const ManifestDiffer();

  /// Computes the changes needed to turn [base] into [target].
  ManifestDiff diff(FileManifest base, FileManifest target) {
    final added = <String>[];
    final modified = <String>[];
    final removed = <String>[];

    for (final path in target.sortedPaths) {
      final before = base.entries[path];
      final after = target.entries[path]!;
      if (before == null) {
        added.add(path);
      } else if (before.hash != after.hash) {
        modified.add(path);
      }
    }
    for (final path in base.sortedPaths) {
      if (!target.entries.containsKey(path)) {
        removed.add(path);
      }
    }
    return ManifestDiff(added: added, modified: modified, removed: removed);
  }
}
