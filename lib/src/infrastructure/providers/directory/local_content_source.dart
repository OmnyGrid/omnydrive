import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../../domain/contracts/content_source.dart';
import '../../../domain/entities/file_manifest.dart';
import '../../../domain/value_objects/content_hash.dart';
import '../../../domain/value_objects/path_filter.dart';
import '../../../shared/errors/domain_exception.dart';
import '../../../shared/errors/error_codes.dart';
import 'manifest_builder.dart';

/// A [ContentSource] backed by a local filesystem directory.
class LocalContentSource implements ContentSource {
  /// Absolute path to the directory root.
  final String root;

  @override
  final bool isWritable;

  final ManifestBuilder _builder;

  /// Creates a content source rooted at [root].
  ///
  /// When [filter] is supplied and no explicit [builder] is given, the manifest
  /// walk applies the filter so only the surviving sub-paths are exposed.
  LocalContentSource(
    this.root, {
    this.isWritable = true,
    PathFilter? filter,
    ManifestBuilder? builder,
  }) : _builder = builder ?? ManifestBuilder(filter: filter);

  @override
  Future<FileManifest> manifest() => _builder.build(root);

  @override
  Future<List<int>> readBytes(String relativePath) async {
    final file = File(_resolve(relativePath));
    if (!await file.exists()) {
      throw NotFoundException(
        code: ErrorCodes.notFound,
        message: 'File not found: $relativePath',
      );
    }
    return file.readAsBytes();
  }

  @override
  Future<void> writeBytes(String relativePath, List<int> bytes) async {
    _ensureWritable();
    final file = File(_resolve(relativePath));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
  }

  @override
  Future<void> delete(String relativePath) async {
    _ensureWritable();
    final file = File(_resolve(relativePath));
    if (await file.exists()) await file.delete();
  }

  @override
  Future<bool> supportsCopy() async => isWritable;

  @override
  Future<bool> copy(
    String fromPath,
    String toPath,
    ContentHash expectedHash,
  ) async {
    _ensureWritable();
    final from = File(_resolve(fromPath));
    if (!await from.exists()) return false;
    final bytes = await from.readAsBytes();
    // Verify the source still holds the expected content before reusing it: the
    // file may have changed between manifest build and this copy.
    final actual = ContentHash(hex: sha256.convert(bytes).toString());
    if (actual != expectedHash) return false;
    final to = File(_resolve(toPath));
    await to.parent.create(recursive: true);
    // Reuse the bytes already read for hashing rather than a second disk read.
    await to.writeAsBytes(bytes, flush: true);
    return true;
  }

  void _ensureWritable() {
    if (!isWritable) {
      throw const AccessDeniedException(
        code: ErrorCodes.readOnlyViolation,
        message: 'Content source is read-only',
      );
    }
  }

  String _resolve(String relativePath) {
    final normalized = p.normalize(relativePath);
    if (p.isAbsolute(normalized) || normalized.startsWith('..')) {
      throw ValidationException('Illegal path escapes root: $relativePath');
    }
    return p.join(root, normalized);
  }
}
