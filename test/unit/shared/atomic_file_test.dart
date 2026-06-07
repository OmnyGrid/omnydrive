import 'dart:io';

import 'package:omnydrive/omnydrive.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../support/temp_dir.dart';

void main() {
  late TempDir tmp;

  setUp(() async => tmp = await TempDir.create());
  tearDown(() async => tmp.cleanup());

  test('writes and re-reads JSON, creating parent directories', () async {
    final path = p.join(tmp.path, 'nested', 'state.json');
    await AtomicFile.writeJson(path, {'a': 1, 'b': 'two'});

    final read = await AtomicFile.readJson(path);
    expect(read, {'a': 1, 'b': 'two'});
  });

  test('readJson returns null for a missing file', () async {
    expect(await AtomicFile.readJson(p.join(tmp.path, 'nope.json')), isNull);
  });

  test('overwrite leaves no temp files behind', () async {
    final path = p.join(tmp.path, 'state.json');
    await AtomicFile.writeJson(path, {'v': 1});
    await AtomicFile.writeJson(path, {'v': 2});

    expect((await AtomicFile.readJson(path))!['v'], 2);
    final leftovers = Directory(
      tmp.path,
    ).listSync().whereType<File>().where((f) => f.path.endsWith('.tmp'));
    expect(leftovers, isEmpty);
  });
}
