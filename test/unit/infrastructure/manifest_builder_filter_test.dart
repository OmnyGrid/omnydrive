import 'package:omnydrive/omnydrive.dart';
import 'package:test/test.dart';

import '../../support/temp_dir.dart';

void main() {
  late TempDir tmp;

  setUp(() async {
    tmp = await TempDir.create('omnydrive_manifest_filter_');
  });
  tearDown(() => tmp.cleanup());

  Future<void> seed() async {
    await tmp.writeFile('keep/a.txt', 'A');
    await tmp.writeFile('keep/nested/b.txt', 'B');
    await tmp.writeFile('secret/p.txt', 'P');
    await tmp.writeFile('notes.tmp', 'N');
    await tmp.writeFile('readme.md', 'R');
  }

  test('excluded sub-paths are omitted from the manifest', () async {
    await seed();
    final builder = ManifestBuilder(
      filter: PathFilter(exclude: ['secret/**', '**/*.tmp']),
    );
    final manifest = await builder.build(tmp.path);
    expect(manifest.sortedPaths, [
      'keep/a.txt',
      'keep/nested/b.txt',
      'readme.md',
    ]);
  });

  test('an include whitelist keeps only matching sub-paths', () async {
    await seed();
    final builder = ManifestBuilder(filter: PathFilter(include: ['keep/**']));
    final manifest = await builder.build(tmp.path);
    expect(manifest.sortedPaths, ['keep/a.txt', 'keep/nested/b.txt']);
  });

  test(
    'a filtered build hashes the same as a tree without the excluded files',
    () async {
      await seed();
      final filtered = await ManifestBuilder(
        filter: PathFilter(exclude: ['secret/**', '**/*.tmp']),
        useCache: false,
      ).build(tmp.path);

      // Physically remove the excluded files and rebuild without a filter.
      await tmp.dir.delete(recursive: true);
      await tmp.writeFile('keep/a.txt', 'A');
      await tmp.writeFile('keep/nested/b.txt', 'B');
      await tmp.writeFile('readme.md', 'R');
      final physical = await const ManifestBuilder(
        useCache: false,
      ).build(tmp.path);

      expect(filtered.hash(), physical.hash());
    },
  );
}
