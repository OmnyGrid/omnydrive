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

  /// Whether this source advertises in-place copy support.
  final bool canCopy;

  /// When true, every [copy] reports a miss (as if the source drifted), forcing
  /// the synchronizer onto its byte-transfer fallback.
  final bool copyFails;

  int inFlight = 0;
  int peakInFlight = 0;

  /// How many [readBytes]/[copy] calls have been served, so tests can prove
  /// duplicate content was copied rather than re-read and re-transferred.
  int reads = 0;
  int copies = 0;

  FakeContentSource({
    Map<String, List<int>>? files,
    this.isWritable = true,
    this.canCopy = true,
    this.copyFails = false,
    this.delay = const Duration(milliseconds: 5),
  }) : files = files ?? {};

  ContentHash _hashOf(List<int> bytes) =>
      ContentHash(hex: sha256.convert(bytes).toString());

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
  Future<List<int>> readBytes(String relativePath) => _tracked(() {
    reads++;
    return files[relativePath]!;
  });

  @override
  Future<void> writeBytes(
    String relativePath,
    List<int> bytes, {
    void Function(int sent, int total)? onProgress,
  }) => _tracked(() {
    // Emit a couple of progress ticks so tests can observe streaming.
    onProgress?.call(0, bytes.length);
    onProgress?.call(bytes.length, bytes.length);
    files[relativePath] = bytes;
  });

  @override
  Future<void> delete(String relativePath) =>
      _tracked(() => files.remove(relativePath));

  @override
  Future<bool> supportsCopy() async => canCopy && isWritable;

  @override
  Future<bool> copy(String fromPath, String toPath, ContentHash expectedHash) =>
      _tracked(() {
        if (copyFails) return false;
        final source = files[fromPath];
        // Verify the source still holds the expected content, mirroring the
        // real sources; a mismatch tells the caller to fall back to a transfer.
        if (source == null || _hashOf(source) != expectedHash) return false;
        copies++;
        files[toPath] = source;
        return true;
      });
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

  test(
    'push sends duplicate content once and copies it to the other paths',
    () async {
      final dup = utf8.encode('shared build artifact');
      final local = FakeContentSource(
        files: {
          'src/lib.js': dup,
          'build/lib.js': dup, // identical content copied into the build dir
          'unique.txt': utf8.encode('one of a kind'),
        },
      );
      final origin = FakeContentSource();
      final baseline = await origin.manifest().then((m) => m.hash());

      final sync = DirectorySynchronizer(
        drive: driveOf(),
        resolveOrigin: ({required bool writable}) => origin,
        resolveLocal: (_) => local,
      );

      final plan = await sync.plan(
        mount: mountOf(baseline),
        baseline: baseline,
        direction: SyncDirection.push,
      );
      final result = await sync.apply(
        mount: mountOf(baseline),
        plan: plan,
        baseline: baseline,
      );

      // Every file arrived intact at the origin.
      expect(
        origin.files.keys,
        containsAll(<String>['src/lib.js', 'build/lib.js', 'unique.txt']),
      );
      expect(origin.files['src/lib.js'], equals(dup));
      expect(origin.files['build/lib.js'], equals(dup));
      expect(result.appliedChanges, equals(3));

      // The duplicate's bytes were read from local exactly once (one
      // representative + the unique file) and reused via a server-side copy.
      expect(local.reads, equals(2));
      expect(origin.copies, equals(1));

      // Only the bytes actually sent count — the deduped copy is free.
      expect(
        result.metrics.bytesTransferred,
        equals(dup.length + 'one of a kind'.length),
      );
    },
  );

  test(
    'pull reuses content the local copy already holds, with no re-download',
    () async {
      final shared = utf8.encode('already on disk');
      // Origin holds the shared content at an existing path plus a brand-new one.
      final origin = FakeContentSource(
        files: {'keep.bin': shared, 'mirror/keep.bin': shared},
      );
      // Local already has it at keep.bin (matching the origin), so the new path
      // can be produced by an in-place copy instead of a download.
      final local = FakeContentSource(files: {'keep.bin': shared});
      final baseline = await local.manifest().then((m) => m.hash());

      final sync = DirectorySynchronizer(
        drive: driveOf(),
        resolveOrigin: ({required bool writable}) => origin,
        resolveLocal: (_) => local,
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

      expect(local.files['mirror/keep.bin'], equals(shared));
      expect(result.appliedChanges, equals(1));
      // The content was reused locally: copied at the dest, never read from origin.
      expect(local.copies, equals(1));
      expect(origin.reads, equals(0));
      expect(result.metrics.bytesTransferred, equals(0));
    },
  );

  test('a drifted copy source falls back to a normal byte transfer', () async {
    final dup = utf8.encode('shared build artifact');
    final local = FakeContentSource(
      files: {'src/lib.js': dup, 'build/lib.js': dup},
    );
    // Origin advertises copy support but every copy misses (source drifted),
    // so the duplicate must be reconstructed by a full transfer.
    final origin = FakeContentSource(copyFails: true);
    final baseline = await origin.manifest().then((m) => m.hash());

    final sync = DirectorySynchronizer(
      drive: driveOf(),
      resolveOrigin: ({required bool writable}) => origin,
      resolveLocal: (_) => local,
    );

    final plan = await sync.plan(
      mount: mountOf(baseline),
      baseline: baseline,
      direction: SyncDirection.push,
    );
    final result = await sync.apply(
      mount: mountOf(baseline),
      plan: plan,
      baseline: baseline,
    );

    // Both files still land correctly despite the failed copy.
    expect(origin.files['src/lib.js'], equals(dup));
    expect(origin.files['build/lib.js'], equals(dup));
    expect(origin.copies, equals(0));
    // Fallback transferred the second copy's bytes too: both paths paid full price.
    expect(result.metrics.bytesTransferred, equals(dup.length * 2));
  });

  test('a dest without copy support transfers every file as before', () async {
    final dup = utf8.encode('shared build artifact');
    final local = FakeContentSource(
      files: {'src/lib.js': dup, 'build/lib.js': dup},
    );
    final origin = FakeContentSource(canCopy: false);
    final baseline = await origin.manifest().then((m) => m.hash());

    final sync = DirectorySynchronizer(
      drive: driveOf(),
      resolveOrigin: ({required bool writable}) => origin,
      resolveLocal: (_) => local,
    );

    final plan = await sync.plan(
      mount: mountOf(baseline),
      baseline: baseline,
      direction: SyncDirection.push,
    );
    final result = await sync.apply(
      mount: mountOf(baseline),
      plan: plan,
      baseline: baseline,
    );

    expect(origin.files['src/lib.js'], equals(dup));
    expect(origin.files['build/lib.js'], equals(dup));
    expect(origin.copies, equals(0));
    expect(local.reads, equals(2));
    expect(result.metrics.bytesTransferred, equals(dup.length * 2));
  });

  test('streams per-file upload progress with size and kind', () async {
    final body = utf8.encode('a sizeable payload for streaming');
    final local = FakeContentSource(files: {'big.bin': body});
    final origin = FakeContentSource();
    final baseline = await origin.manifest().then((m) => m.hash());

    final sync = DirectorySynchronizer(
      drive: driveOf(),
      resolveOrigin: ({required bool writable}) => origin,
      resolveLocal: (_) => local,
    );

    final events = <ProgressEvent>[];
    final plan = await sync.plan(
      mount: mountOf(baseline),
      baseline: baseline,
      direction: SyncDirection.push,
    );
    await sync.apply(
      mount: mountOf(baseline),
      plan: plan,
      baseline: baseline,
      progress: ProgressReporter(events.add),
    );

    final forFile = events.where((e) => e.path == 'big.bin').toList();
    // The file moves through started -> progress -> completed, all tagged as a
    // transfer and carrying the original (uncompressed) size.
    expect(
      forFile.map((e) => e.itemState),
      containsAllInOrder([
        ProgressItemState.started,
        ProgressItemState.progress,
        ProgressItemState.completed,
      ]),
    );
    expect(
      forFile.every((e) => e.itemKind == ProgressItemKind.transferred),
      isTrue,
    );
    expect(forFile.every((e) => e.itemSize == body.length), isTrue);

    // Streaming progress advances the per-file byte count to the full size.
    final streamed = forFile.where(
      (e) => e.itemState == ProgressItemState.progress,
    );
    expect(streamed, isNotEmpty);
    expect(streamed.last.itemBytes, equals(body.length));
  });

  test(
    'final report lists transferred and copied paths with wire bytes',
    () async {
      final dup = utf8.encode('shared build artifact');
      final local = FakeContentSource(
        files: {
          'src/lib.js': dup,
          'build/lib.js': dup, // deduplicated copy of src/lib.js
          'unique.txt': utf8.encode('one of a kind'),
        },
      );
      final origin = FakeContentSource();
      final baseline = await origin.manifest().then((m) => m.hash());

      final sync = DirectorySynchronizer(
        drive: driveOf(),
        resolveOrigin: ({required bool writable}) => origin,
        resolveLocal: (_) => local,
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

      final metrics = result.metrics;
      // Exactly one of the duplicate pair is deduplicated (which one is the
      // representative depends on iteration order); the rest are transferred.
      expect(metrics.filesCopied, equals(1));
      expect(metrics.filesTransferred, equals(2));
      expect(metrics.copiedPaths.single, anyOf('src/lib.js', 'build/lib.js'));
      expect(metrics.transferredPaths, contains('unique.txt'));
      // The pair's representative is whichever wasn't copied.
      final copied = metrics.copiedPaths.single;
      final representative = copied == 'src/lib.js'
          ? 'build/lib.js'
          : 'src/lib.js';
      expect(metrics.transferredPaths, contains(representative));
      // The fake doesn't compress, so wire bytes equal the raw transferred bytes.
      expect(metrics.bytesOnWire, equals(metrics.bytesTransferred));
      expect(metrics.bytesOnWire, greaterThan(0));

      // The copied path's completion event is tagged accordingly.
      final copyDone = events.firstWhere(
        (e) => e.path == copied && e.itemState == ProgressItemState.completed,
      );
      expect(copyDone.itemKind, equals(ProgressItemKind.copied));
    },
  );
}
