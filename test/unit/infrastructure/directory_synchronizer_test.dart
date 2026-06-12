import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:omnydrive/omnydrive.dart';
import 'package:test/test.dart';

/// In-memory [ContentSource] that records peak read/write concurrency and adds
/// a small delay to each transfer so overlap is observable.
class FakeContentSource implements ContentSource {
  final Map<String, List<int>> files;
  final Duration delay;

  @override
  final bool isWritable;

  int inFlight = 0;
  int peakInFlight = 0;

  FakeContentSource({
    Map<String, List<int>>? files,
    this.isWritable = true,
    this.delay = const Duration(milliseconds: 5),
  }) : files = files ?? {};

  Future<T> _tracked<T>(FutureOr<T> Function() body) async {
    inFlight++;
    peakInFlight = peakInFlight > inFlight ? peakInFlight : inFlight;
    try {
      await Future<void>.delayed(delay);
      return await body();
    } finally {
      inFlight--;
    }
  }

  @override
  Future<FileManifest> manifest() async {
    final entries = <String, FileManifestEntry>{};
    for (final entry in files.entries) {
      final bytes = entry.value;
      final digest = sha256.convert(bytes);
      entries[entry.key] = FileManifestEntry(
        path: entry.key,
        size: bytes.length,
        hash: ContentHash(hex: digest.toString()),
      );
    }
    return FileManifest(entries);
  }

  @override
  Future<List<int>> readBytes(String relativePath) =>
      _tracked(() => files[relativePath]!);

  @override
  Future<void> writeBytes(String relativePath, List<int> bytes) =>
      _tracked(() => files[relativePath] = bytes);

  @override
  Future<void> delete(String relativePath) =>
      _tracked(() => files.remove(relativePath));
}

void main() {
  Drive driveOf() => Drive(
    id: DriveId('nas/photos'),
    name: 'photos',
    provider: ProviderType.directory,
    originEndpoint: EndpointId('nas'),
    originUri: OriginUri('file:///tmp/photos'),
    accessMode: AccessMode.readWrite,
    capabilities: DriveCapabilities.forProvider(
      ProviderType.directory,
      AccessMode.readWrite,
    ),
    createdAt: DateTime.utc(2026),
  );

  MountInfo mountOf(SyncRef baseline) => MountInfo(
    id: MountId('m1'),
    driveId: DriveId('nas/photos'),
    localPath: LocalPath('/tmp/mirror'),
    accessMode: AccessMode.readWrite,
    mountType: MountType.mirror,
    mountedAt: DateTime.utc(2026),
    syncState: SyncState(baselineRef: baseline),
  );

  test(
    'pushes many files concurrently, capped at transferConcurrency',
    () async {
      final local = FakeContentSource(
        files: {
          for (var i = 0; i < 30; i++)
            'file_$i.bin': utf8.encode('contents of file $i'),
        },
      );
      final origin = FakeContentSource();
      final baseline = await origin.manifest().then((m) => m.hash());

      final sync = DirectorySynchronizer(
        drive: driveOf(),
        resolveOrigin: ({required bool writable}) => origin,
        resolveLocal: (_) => local,
        transferConcurrency: 4,
      );

      final events = <ProgressEvent>[];
      final plan = await sync.plan(
        mount: mountOf(baseline),
        baseline: baseline,
        direction: SyncDirection.push,
      );
      final result = await sync.apply(
        mount: mountOf(baseline),
        plan: plan,
        baseline: baseline,
        progress: ProgressReporter(events.add),
      );

      // All files arrived at the origin.
      expect(origin.files, hasLength(30));
      expect(result.appliedChanges, equals(30));

      // Transfers overlapped (proves it is not serial) but stayed within bounds.
      expect(origin.peakInFlight, greaterThan(1));
      expect(origin.peakInFlight, lessThanOrEqualTo(4));

      // Final transfer event accounts for every file and the full byte total.
      final last = events.lastWhere(
        (e) => e.phase == ProgressPhase.transferring,
      );
      expect(last.completed, equals(last.total));
      expect(last.total, equals(30));
      final expectedBytes = local.files.values.fold<int>(
        0,
        (sum, b) => sum + b.length,
      );
      expect(result.metrics.bytesTransferred, equals(expectedBytes));
    },
  );

  test(
    'pull transfers concurrently and matches the serial byte total',
    () async {
      final origin = FakeContentSource(
        files: {
          for (var i = 0; i < 20; i++) 'doc_$i.txt': utf8.encode('doc body $i'),
        },
      );
      final local = FakeContentSource();
      final baseline = await local.manifest().then((m) => m.hash());

      final sync = DirectorySynchronizer(
        drive: driveOf(),
        resolveOrigin: ({required bool writable}) => origin,
        resolveLocal: (_) => local,
        transferConcurrency: 8,
      );

      final plan = await sync.plan(
        mount: mountOf(baseline),
        baseline: baseline,
        direction: SyncDirection.pull,
      );
      final result = await sync.apply(
        mount: mountOf(baseline),
        plan: plan,
        baseline: baseline,
      );

      expect(local.files, hasLength(20));
      expect(result.appliedChanges, equals(20));
      expect(local.peakInFlight, greaterThan(1));
      expect(local.peakInFlight, lessThanOrEqualTo(8));
      final expectedBytes = origin.files.values.fold<int>(
        0,
        (sum, b) => sum + b.length,
      );
      expect(result.metrics.bytesTransferred, equals(expectedBytes));
    },
  );
}
