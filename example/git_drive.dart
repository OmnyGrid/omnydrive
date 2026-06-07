// Demonstrates a git-backed drive: publish a local repository, clone it on
// another endpoint, commit locally, and publish that commit back to the origin
// as a fresh feature branch (OmnyDrive never pushes to a protected branch).
//
// A local commit is what makes a git sync a *push* — uncommitted working-tree
// edits do not move HEAD, so `syncMount` would treat the mirror as unchanged.
//
// Requires the `git` binary. Run with: dart run example/git_drive.dart

import 'dart:io';

import 'package:omnydrive/omnydrive.dart';

import 'scenario.dart';

Future<void> main() async {
  if (!await GitCli.isAvailable()) {
    print('git is not installed — skipping the git drive example.');
    return;
  }

  const git = GitCli();
  final s = await Scenario.start();
  try {
    // --- Build a local origin repository with one commit -------------------
    final origin = s.dir('origin');
    await git.init(origin);
    File('$origin/main.dart').writeAsStringSync('void main() {}\n');
    await git.addAll(origin);
    await git.commit(origin, 'initial commit');
    print('origin repository ready');

    final alpha = await s.publisher('alpha');
    final drive = await alpha.publishGit(url: origin, name: 'app');
    print('published ${drive.id} (${drive.provider.wireValue})');

    // --- Clone it on another endpoint --------------------------------------
    final beta = await s.cloner('beta');
    final clone = s.dir('clone');
    final mount = await beta.cloneDrive(driveId: drive.id.value, dest: clone);
    print('cloned to a working copy');

    // --- Commit locally, then publish the commit ---------------------------
    File('$clone/feature.dart').writeAsStringSync('// new feature\n');
    await git.addAll(clone);
    await git.commit(clone, 'add feature');

    final result = await beta.syncMount(mount.id.value);
    final branch = result.publishedBranch!;
    final sha = await git.branchSha(origin, branch);
    print('\npushed to feature branch: $branch');
    print('origin now has $branch at ${sha?.substring(0, 8)}');
  } finally {
    await s.stop();
  }
}
