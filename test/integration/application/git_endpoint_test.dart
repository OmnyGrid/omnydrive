import 'dart:io';

import 'package:omnydrive/omnydrive.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../support/fixed_clock.dart';
import '../../support/temp_dir.dart';

/// End-to-end git sync through `LocalDriveEndpoint.syncMount`: publish a git
/// drive, clone it on another endpoint, and exercise the direction decision.
/// The defining behaviour for a read-write git mount is that publishing local
/// commits creates a *fresh feature branch* on the origin — never a write to
/// the protected branch.
void main() {
  const git = GitCli();
  final t0 = DateTime.utc(2026, 1, 1);

  EndpointIdentity ident(String id) => EndpointIdentity(
    id: EndpointId(id),
    displayName: id,
    baseUrl: 'http://$id.local',
    capabilities: CapabilitySet([
      Capability.read,
      Capability.write,
      Capability.clone,
      Capability.mirror,
    ]),
    registeredAt: t0,
  );

  late LocalDriveHub hub;
  late LocalDriveEndpoint publisher;
  late LocalDriveEndpoint cloner;
  late TempDir origin;
  late TempDir work;

  setUp(() async {
    hub = LocalDriveHub(
      idGenerator: SequentialIdGenerator(),
      clock: FixedClock(t0),
    );
    await hub.enroll(identity: ident('alpha'));
    await hub.enroll(identity: ident('beta'));
    publisher = LocalDriveEndpoint(
      identity: ident('alpha'),
      hub: hub,
      idGenerator: SequentialIdGenerator(),
      clock: FixedClock(t0),
    );
    cloner = LocalDriveEndpoint(
      identity: ident('beta'),
      hub: hub,
      idGenerator: SequentialIdGenerator(),
      clock: FixedClock(t0),
    );
    origin = await TempDir.create('omnydrive_git_origin_');
    work = await TempDir.create('omnydrive_git_work_');
  });

  tearDown(() async {
    await origin.cleanup();
    await work.cleanup();
  });

  void gitTest(String description, Future<void> Function() body) {
    test(description, () async {
      if (!await GitCli.isAvailable()) {
        markTestSkipped('git binary not available');
        return;
      }
      await body();
    });
  }

  /// Initialises the origin repo with one commit and returns its protected
  /// (default) branch name.
  Future<String> initOrigin() async {
    await git.init(origin.path);
    await origin.writeFile('main.dart', 'void main() {}\n');
    await git.addAll(origin.path);
    await git.commit(origin.path, 'initial commit');
    return git.currentBranch(origin.path);
  }

  /// Publishes the origin as a git drive and clones it, returning the clone
  /// path and the mount.
  Future<({String dest, MountInfo mount})> publishAndClone({
    bool readOnly = false,
  }) async {
    final drive = await publisher.publishGit(url: origin.path, name: 'app');
    final dest = p.join(work.path, 'clone');
    final mount = await cloner.cloneDrive(
      driveId: drive.id.value,
      dest: dest,
      readOnly: readOnly,
    );
    return (dest: dest, mount: mount);
  }

  Future<void> commitLocal(String path, String file, String contents) async {
    await File(p.join(path, file)).writeAsString(contents);
    await git.addAll(path);
    await git.commit(path, 'local: $file');
  }

  gitTest(
    'a read-write mount publishes local commits to a fresh feature branch',
    () async {
      final protectedBranch = await initOrigin();
      final protectedShaBefore = await git.branchSha(
        origin.path,
        protectedBranch,
      );
      final m = await publishAndClone();

      await commitLocal(m.dest, 'feature.dart', '// feature\n');
      final localSha = await git.revParse(m.dest);

      final result = await cloner.syncMount(m.mount.id.value);

      expect(result.status, SyncStatus.clean);
      expect(result.publishedBranch, 'omnydrive/update-1');
      expect(await git.branchSha(origin.path, 'omnydrive/update-1'), localSha);
      expect(
        await git.branchSha(origin.path, protectedBranch),
        protectedShaBefore,
        reason: 'the protected branch must not move',
      );
    },
  );

  gitTest('a clean mount with no local commits is a no-op', () async {
    await initOrigin();
    final m = await publishAndClone();

    final result = await cloner.syncMount(m.mount.id.value);
    expect(result.status, SyncStatus.clean);
    expect(result.appliedChanges, 0);
    expect(result.publishedBranch, isNull);
  });

  gitTest(
    'a mount pulls new origin commits when it has no local work',
    () async {
      await initOrigin();
      final m = await publishAndClone();

      // The origin advances after the clone.
      await commitLocal(origin.path, 'added.dart', '// added\n');
      final originSha = await git.revParse(origin.path);

      final result = await cloner.syncMount(m.mount.id.value);
      expect(result.status, SyncStatus.clean);
      expect(await git.revParse(m.dest), originSha);
      expect(File(p.join(m.dest, 'added.dart')).existsSync(), isTrue);
    },
  );

  gitTest('a read-only mount with a local commit conflicts', () async {
    await initOrigin();
    final m = await publishAndClone(readOnly: true);
    expect(m.mount.accessMode, AccessMode.readOnly);

    await commitLocal(m.dest, 'feature.dart', '// feature\n');
    final localSha = await git.revParse(m.dest);

    // A read-only mount cannot push, so the local divergence is surfaced as a
    // conflict rather than being silently discarded by a pull.
    await expectLater(
      () => cloner.syncMount(m.mount.id.value),
      throwsA(isA<ConflictDetectedException>()),
    );
    expect(await git.revParse(m.dest), localSha);
  });
}
