import 'package:omnydrive/omnydrive.dart';
import 'package:test/test.dart';

void main() {
  final driveId = DriveId.scoped(endpoint: EndpointId('nas'), name: 'docs');

  group('ConflictDetector', () {
    const detector = ConflictDetector();

    test('no conflict when origin still at baseline', () {
      final c = detector.detectForPush(
        driveId: driveId,
        baseline: SyncRef.directory('a'),
        origin: SyncRef.directory('a'),
      );
      expect(c, isNull);
    });

    test('refMoved conflict when origin advanced', () {
      final c = detector.detectForPush(
        driveId: driveId,
        baseline: SyncRef.directory('a'),
        origin: SyncRef.directory('b'),
      );
      expect(c, isNotNull);
      expect(c!.kind, ConflictKind.refMoved);
      expect(c.expectedRef, SyncRef.directory('a'));
      expect(c.actualRef, SyncRef.directory('b'));
    });

    test('no pull conflict when the local copy still matches baseline', () {
      final c = detector.detectForPull(
        driveId: driveId,
        baseline: SyncRef.directory('a'),
        local: SyncRef.directory('a'),
        origin: SyncRef.directory('b'),
      );
      expect(c, isNull);
    });

    test('localDivergence when only the local copy moved (cannot push)', () {
      final c = detector.detectForPull(
        driveId: driveId,
        baseline: SyncRef.directory('a'),
        local: SyncRef.directory('b'),
        origin: SyncRef.directory('a'),
      );
      expect(c, isNotNull);
      expect(c!.kind, ConflictKind.localDivergence);
      expect(c.actualRef, SyncRef.directory('b'));
    });

    test('contentDivergence when both the local copy and origin moved', () {
      final c = detector.detectForPull(
        driveId: driveId,
        baseline: SyncRef.directory('a'),
        local: SyncRef.directory('b'),
        origin: SyncRef.directory('c'),
      );
      expect(c, isNotNull);
      expect(c!.kind, ConflictKind.contentDivergence);
    });
  });

  group('ManifestDiffer', () {
    const differ = ManifestDiffer();

    FileManifest m(Map<String, String> pathToHash) => FileManifest({
      for (final e in pathToHash.entries)
        e.key: FileManifestEntry(
          path: e.key,
          size: 1,
          hash: ContentHash(hex: e.value),
        ),
    });

    test('detects added, modified, removed', () {
      final base = m({'keep.txt': 'aa', 'change.txt': 'bb', 'gone.txt': 'cc'});
      final target = m({'keep.txt': 'aa', 'change.txt': 'dd', 'new.txt': 'ee'});
      final diff = differ.diff(base, target);
      expect(diff.added, ['new.txt']);
      expect(diff.modified, ['change.txt']);
      expect(diff.removed, ['gone.txt']);
    });

    test('empty diff for identical manifests', () {
      final a = m({'x': 'aa'});
      expect(differ.diff(a, a).isEmpty, isTrue);
    });

    test('an executable-bit change counts as modified', () {
      FileManifest withExec(bool exec) => FileManifest({
        'run.sh': FileManifestEntry(
          path: 'run.sh',
          size: 1,
          hash: ContentHash(hex: 'aa'),
          executable: exec,
        ),
      });
      // Identical content, only the exec bit flips — must still be reported.
      final diff = differ.diff(withExec(false), withExec(true));
      expect(diff.modified, ['run.sh']);
      expect(diff.added, isEmpty);
      expect(diff.removed, isEmpty);
    });
  });

  group('CapabilityNegotiator', () {
    const negotiator = CapabilityNegotiator();
    final supported = CapabilitySet([
      Capability.read,
      Capability.write,
      Capability.push,
      Capability.clone,
    ]);

    test('read-only strips write capabilities', () {
      final effective = negotiator.negotiate(
        supported: supported,
        requested: AccessMode.readOnly,
      );
      expect(effective.has(Capability.read), isTrue);
      expect(effective.has(Capability.clone), isTrue);
      expect(effective.has(Capability.write), isFalse);
      expect(effective.has(Capability.push), isFalse);
    });

    test('read-write keeps everything', () {
      final effective = negotiator.negotiate(
        supported: supported,
        requested: AccessMode.readWrite,
      );
      expect(effective, equals(supported));
    });

    test('permits enforces access mode', () {
      expect(
        negotiator.permits(
          supported: supported,
          accessMode: AccessMode.readOnly,
          capability: Capability.push,
        ),
        isFalse,
      );
    });
  });

  group('DefaultBranchNamingStrategy', () {
    test('increments update branches', () {
      final strategy = DefaultBranchNamingStrategy();
      expect(strategy.nextBranch().value, 'omnydrive/update-1');
      expect(strategy.nextBranch().value, 'omnydrive/update-2');
    });
    test('uses label when provided', () {
      final strategy = DefaultBranchNamingStrategy();
      expect(strategy.nextBranch(label: 'Job 42').value, 'omnydrive/job-42');
    });
    test('produced branches are not protected', () {
      final strategy = DefaultBranchNamingStrategy();
      expect(strategy.nextBranch().isProtected(), isFalse);
    });
  });
}
