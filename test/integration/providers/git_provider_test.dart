import 'dart:io';

import 'package:omnydrive/omnydrive.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../support/temp_dir.dart';

/// Integration tests for the git provider/synchronizer against a real `git`
/// binary and on-disk repositories. The headline behaviour is that a
/// read-write mount never writes to the protected branch: a push publishes
/// local commits to a *fresh* feature branch on the origin.
void main() {
  const git = GitCli();
  late TempDir origin; // a non-bare origin repository
  late TempDir work; // holds the cloned working copies

  setUp(() async {
    origin = await TempDir.create('omnydrive_git_origin_');
    work = await TempDir.create('omnydrive_git_work_');
  });

  tearDown(() async {
    await origin.cleanup();
    await work.cleanup();
  });

  // Runs [body] only when a git binary is present, skipping otherwise so the
  // suite stays green on machines without git.
  void gitTest(String description, Future<void> Function() body) {
    test(description, () async {
      if (!await GitCli.isAvailable()) {
        markTestSkipped('git binary not available');
        return;
      }
      await body();
    });
  }

  // --- Helpers --------------------------------------------------------------

  OriginUri originUri() => OriginUri(origin.path);

  /// Initialises [origin] as a repository with a single committed file and
  /// returns the name of its (protected) default branch.
  Future<String> initOrigin() async {
    await git.init(origin.path);
    await origin.writeFile('main.dart', 'void main() {}\n');
    await git.addAll(origin.path);
    await git.commit(origin.path, 'initial commit');
    return git.currentBranch(origin.path);
  }

  GitProvider newProvider() => GitProvider(
    endpoint: EndpointId('nas'),
    branchNaming: DefaultBranchNamingStrategy(),
  );

  /// Clones [origin] into a working copy and returns the drive, the clone path
  /// and the recorded baseline ref.
  Future<({Drive drive, LocalPath dest, SyncRef baseline})> mount(
    GitProvider provider, {
    AccessMode mode = AccessMode.readWrite,
  }) async {
    final drive = await provider.describe(originUri(), accessMode: mode);
    final dest = LocalPath(p.join(work.path, 'clone'));
    final mounted = await provider.materialize(
      drive: drive,
      dest: dest,
      mountType: MountType.mirror,
    );
    return (
      drive: drive,
      dest: dest,
      baseline: mounted.info.syncState.baselineRef,
    );
  }

  MountInfo mountInfo(Drive drive, LocalPath dest, SyncRef baseline) =>
      MountInfo(
        id: MountId('m1'),
        driveId: drive.id,
        localPath: dest,
        accessMode: drive.accessMode,
        mountType: MountType.mirror,
        mountedAt: DateTime.utc(2026),
        syncState: SyncState(baselineRef: baseline),
      );

  /// Commits [file] in the working copy at [path], moving HEAD (which is what
  /// turns a git sync into a push).
  Future<void> commitLocal(String path, String file, String contents) async {
    await File(p.join(path, file)).writeAsString(contents);
    await git.addAll(path);
    await git.commit(path, 'local: $file');
  }

  // --- Materialize ----------------------------------------------------------

  gitTest(
    'materialize clones the repo and records the head baseline',
    () async {
      await initOrigin();
      final originSha = await git.revParse(origin.path);

      final provider = newProvider();
      final m = await mount(provider);

      expect(File(p.join(m.dest.value, 'main.dart')).existsSync(), isTrue);
      expect(m.baseline, SyncRef.git(originSha));
    },
  );

  gitTest('a read-only mount clones the content too', () async {
    await initOrigin();
    await commitLocal(origin.path, 'second.dart', '// second\n');
    final originSha = await git.revParse(origin.path);

    final provider = newProvider();
    final m = await mount(provider, mode: AccessMode.readOnly);

    expect(m.drive.accessMode, AccessMode.readOnly);
    expect(File(p.join(m.dest.value, 'second.dart')).existsSync(), isTrue);
    // The tip is mirrored regardless of clone depth.
    expect(await git.revParse(m.dest.value), originSha);
  });

  gitTest('currentRef resolves the origin HEAD sha', () async {
    await initOrigin();
    final provider = newProvider();
    final ref = await provider.currentRef(originUri());
    expect(ref, SyncRef.git(await git.revParse(origin.path)));
  });

  // --- Push (local → fresh feature branch) ----------------------------------

  gitTest('push publishes local commits to a fresh feature branch', () async {
    final protectedBranch = await initOrigin();
    final protectedShaBefore = await git.branchSha(
      origin.path,
      protectedBranch,
    );

    final provider = newProvider();
    final m = await mount(provider);
    await commitLocal(m.dest.value, 'feature.dart', '// new feature\n');
    final localSha = await git.revParse(m.dest.value);

    final sync = provider.synchronizer(m.drive);
    final info = mountInfo(m.drive, m.dest, m.baseline);
    final plan = await sync.plan(
      mount: info,
      baseline: m.baseline,
      direction: SyncDirection.push,
    );
    expect(plan.changedPaths, contains('feature.dart'));

    final result = await sync.apply(
      mount: info,
      plan: plan,
      baseline: m.baseline,
    );

    // A new feature branch carries the commit...
    expect(result.publishedBranch, 'omnydrive/update-1');
    expect(await git.branchSha(origin.path, 'omnydrive/update-1'), localSha);
    // ...and the protected branch is left exactly where it was.
    expect(
      await git.branchSha(origin.path, protectedBranch),
      protectedShaBefore,
      reason: 'a push must never move the protected branch',
    );
  });

  gitTest('a push reports the files changed since the baseline', () async {
    await initOrigin();
    final provider = newProvider();
    final m = await mount(provider);
    await commitLocal(m.dest.value, 'a.dart', '// a\n');
    await commitLocal(m.dest.value, 'b.dart', '// b\n');

    final sync = provider.synchronizer(m.drive);
    final info = mountInfo(m.drive, m.dest, m.baseline);
    final plan = await sync.plan(
      mount: info,
      baseline: m.baseline,
      direction: SyncDirection.push,
    );
    expect(plan.changedPaths, containsAll(['a.dart', 'b.dart']));
  });

  gitTest('push raises a conflict when the origin branch moved', () async {
    await initOrigin();
    final provider = newProvider();
    final m = await mount(provider);
    await commitLocal(m.dest.value, 'feature.dart', '// feature\n');

    // The origin's protected branch advances past the baseline.
    await commitLocal(origin.path, 'hotfix.dart', '// hotfix\n');

    final sync = provider.synchronizer(m.drive);
    final info = mountInfo(m.drive, m.dest, m.baseline);
    final plan = await sync.plan(
      mount: info,
      baseline: m.baseline,
      direction: SyncDirection.push,
    );
    expect(plan.requiresConflictResolution, isTrue);

    await expectLater(
      sync.apply(mount: info, plan: plan, baseline: m.baseline),
      throwsA(isA<ConflictDetectedException>()),
    );
  });

  gitTest('consecutive pushes publish incrementing feature branches', () async {
    await initOrigin();
    final provider = newProvider();
    final m = await mount(provider);
    final sync = provider.synchronizer(m.drive);

    await commitLocal(m.dest.value, 'one.dart', '// 1\n');
    var info = mountInfo(m.drive, m.dest, m.baseline);
    var plan = await sync.plan(
      mount: info,
      baseline: m.baseline,
      direction: SyncDirection.push,
    );
    final first = await sync.apply(
      mount: info,
      plan: plan,
      baseline: m.baseline,
    );
    expect(first.publishedBranch, 'omnydrive/update-1');

    // The next push builds on the previous result's ref.
    await commitLocal(m.dest.value, 'two.dart', '// 2\n');
    info = mountInfo(m.drive, m.dest, first.newRef);
    plan = await sync.plan(
      mount: info,
      baseline: first.newRef,
      direction: SyncDirection.push,
    );
    final second = await sync.apply(
      mount: info,
      plan: plan,
      baseline: first.newRef,
    );
    expect(second.publishedBranch, 'omnydrive/update-2');

    expect(await git.branchSha(origin.path, 'omnydrive/update-1'), isNotNull);
    expect(await git.branchSha(origin.path, 'omnydrive/update-2'), isNotNull);
  });

  // --- Pull (origin → mount) ------------------------------------------------

  gitTest('pull fast-forwards the mount to new origin commits', () async {
    await initOrigin();
    final provider = newProvider();
    final m = await mount(provider);

    await commitLocal(origin.path, 'added.dart', '// added\n');
    final originSha = await git.revParse(origin.path);

    final sync = provider.synchronizer(m.drive);
    final info = mountInfo(m.drive, m.dest, m.baseline);
    final plan = await sync.plan(
      mount: info,
      baseline: m.baseline,
      direction: SyncDirection.pull,
    );
    final result = await sync.apply(
      mount: info,
      plan: plan,
      baseline: m.baseline,
    );

    expect(result.newRef, SyncRef.git(originSha));
    expect(await git.revParse(m.dest.value), originSha);
    expect(File(p.join(m.dest.value, 'added.dart')).existsSync(), isTrue);
  });

  gitTest(
    'pull fetches by branch name so it works when origin/<branch> is absent',
    () async {
      // Regression: a pull used to run `git merge --ff-only origin/<branch>`,
      // which fails ("not something we can merge") when the remote-tracking ref
      // does not exist — e.g. a single-branch/shallow clone checked out on a
      // branch other than the one it tracks. The fix fetches the branch by name
      // and fast-forwards to FETCH_HEAD.
      final mainB = await initOrigin(); // origin: main @ C0

      // origin: a `feature` branch one commit ahead of main.
      await git.checkoutNewBranch(origin.path, 'feature');
      await origin.writeFile('feature.dart', '// feature\n');
      await git.addAll(origin.path);
      await git.commit(origin.path, 'feature commit');
      final featSha = await git.revParse(origin.path);
      await git.checkout(origin.path, mainB); // leave origin on main

      // Shallow single-branch clone of main → narrowed fetch refspec, so
      // `origin/feature` is never created; then check out a local `feature`.
      final dest = p.join(work.path, 'clone');
      await git.clone(origin.path, dest, branch: mainB, depth: 1);
      await git.checkoutNewBranch(dest, 'feature');

      // Precondition: the remote-tracking ref for the current branch is absent,
      // so the old `merge origin/feature` would fail.
      final tracking = await git.run(
        ['rev-parse', '--verify', '--quiet', 'refs/remotes/origin/feature'],
        workingDirectory: dest,
        allowFailure: true,
      );
      expect(tracking.ok, isFalse);

      // The fixed pull primitive: fetch by name, fast-forward to FETCH_HEAD.
      await git.fetch(dest, branch: 'feature');
      await git.mergeFastForward(dest, 'FETCH_HEAD');

      expect(await git.revParse(dest), featSha);
      expect(File(p.join(dest, 'feature.dart')).existsSync(), isTrue);
    },
  );
}
