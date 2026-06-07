// Demonstrates OmnyDrive's conflict-first synchronization: a push is refused
// when the origin has moved off the baseline the mirror was cloned from, then
// shows how to resolve it by accepting the origin and re-applying the change.
//
// Run with: dart run example/conflict_detection.dart

import 'dart:io';

import 'package:omnydrive/omnydrive.dart';

import 'scenario.dart';

Future<void> main() async {
  final s = await Scenario.start();
  try {
    final origin = s.dir('origin');
    File('$origin/config.yaml').writeAsStringSync('mode: base\n');

    final alpha = await s.publisher('alpha');
    final drive = await alpha.publishDirectory(path: origin, name: 'config');
    print('published ${drive.id}');

    final beta = await s.cloner('beta');
    final mirror = s.dir('mirror');
    final mount = await beta.cloneDrive(driveId: drive.id.value, dest: mirror);
    print('cloned to a mirror\n');

    // Both sides change the same file after the mirror's baseline was taken.
    File('$origin/config.yaml').writeAsStringSync('mode: origin-edit\n');
    File('$mirror/config.yaml').writeAsStringSync('mode: mirror-edit\n');

    print('pushing the mirror while the origin has also moved...');
    try {
      await beta.syncMount(mount.id.value);
      print('  unexpected: the push succeeded');
    } on ConflictDetectedException catch (e) {
      final c = e.conflict;
      print('  conflict detected [${c.kind.wireValue}]');
      print('    expected baseline: ${c.expectedRef}');
      print('    actual origin:     ${c.actualRef}');
    }

    // Resolve by accepting the origin: re-clone for a fresh baseline, redo the
    // edit on top of the origin's current content, then push cleanly.
    print('\nresolving — re-clone, re-apply, push...');
    final reclone = s.dir('mirror-reconciled');
    final mount2 = await beta.cloneDrive(
      driveId: drive.id.value,
      dest: reclone,
    );
    print(
      '  re-cloned origin content: '
      '${File('$reclone/config.yaml').readAsStringSync().trim()}',
    );

    File('$reclone/config.yaml').writeAsStringSync('mode: reconciled\n');
    final result = await beta.syncMount(mount2.id.value);
    print('  pushed ${result.appliedChanges} change(s)');
    print(
      '  origin now: '
      '${File('$origin/config.yaml').readAsStringSync().trim()}',
    );
  } finally {
    await s.stop();
  }
}
