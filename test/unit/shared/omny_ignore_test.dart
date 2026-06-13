import 'package:omnydrive/omnydrive.dart';
import 'package:test/test.dart';

import '../../support/temp_dir.dart';

void main() {
  group('parseOmnyIgnore', () {
    test('keeps patterns, trims them, and preserves order', () {
      final patterns = parseOmnyIgnore('build/\n  *.tmp  \nsecret/**\n');
      expect(patterns, ['build/', '*.tmp', 'secret/**']);
    });

    test('drops blank lines and # comments', () {
      final patterns = parseOmnyIgnore('''
# build artifacts
build/

   # indented comment
*.log
''');
      expect(patterns, ['build/', '*.log']);
    });

    test('skips unsupported negation lines', () {
      final patterns = parseOmnyIgnore('build/\n!build/keep.txt\n*.tmp');
      expect(patterns, ['build/', '*.tmp']);
    });

    test('empty content yields no patterns', () {
      expect(parseOmnyIgnore(''), isEmpty);
      expect(parseOmnyIgnore('\n\n   \n'), isEmpty);
    });
  });

  group('loadOmnyIgnore', () {
    late TempDir dir;

    setUp(() async {
      dir = await TempDir.create('omnydrive_ignore_');
      addTearDown(dir.cleanup);
    });

    test('returns an empty list when the file is absent', () async {
      expect(await loadOmnyIgnore(dir.path), isEmpty);
    });

    test('reads and parses the default .omnyignore', () async {
      await dir.writeFile(omnyIgnoreFileName, '# skip\nbuild/\n*.tmp\n');
      expect(await loadOmnyIgnore(dir.path), ['build/', '*.tmp']);
    });

    test('honors a custom file name', () async {
      await dir.writeFile('.driveignore', 'secret/**\n');
      expect(await loadOmnyIgnore(dir.path), isEmpty);
      expect(await loadOmnyIgnore(dir.path, fileName: '.driveignore'), [
        'secret/**',
      ]);
    });
  });
}
