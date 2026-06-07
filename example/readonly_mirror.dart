// Demonstrates a read-only mirror: a clone taken with readOnly:true never
// publishes local edits, but pulls the origin's changes down on each sync.
//
// Run with: dart run example/readonly_mirror.dart

import 'dart:io';

import 'scenario.dart';

Future<void> main() async {
  final s = await Scenario.start();
  try {
    final origin = s.dir('origin');
    File('$origin/notes.txt').writeAsStringSync('v1\n');

    final alpha = await s.publisher('alpha');
    final drive = await alpha.publishDirectory(path: origin, name: 'notes');

    final beta = await s.cloner('beta');
    final mirror = s.dir('mirror');
    final mount = await beta.cloneDrive(
      driveId: drive.id.value,
      dest: mirror,
      readOnly: true,
    );
    print('mirror access mode: ${mount.accessMode.wireValue}');
    print('  before: ${File('$mirror/notes.txt').readAsStringSync().trim()}');

    // The origin advances independently.
    File('$origin/notes.txt').writeAsStringSync('v2\n');
    File('$origin/extra.txt').writeAsStringSync('added on origin\n');

    final result = await beta.syncMount(mount.id.value);
    print('\npulled ${result.appliedChanges} change(s)');
    print('  after:  ${File('$mirror/notes.txt').readAsStringSync().trim()}');
    print('  extra:  ${File('$mirror/extra.txt').readAsStringSync().trim()}');
  } finally {
    await s.stop();
  }
}
