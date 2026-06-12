import 'dart:convert';
import 'dart:io';

import 'package:omnydrive/omnydrive.dart';
import 'package:test/test.dart';

import '../../support/temp_dir.dart';

void main() {
  late TempDir tmp;

  setUp(() async {
    tmp = await TempDir.create('omnydrive_manifest_cache_');
  });
  tearDown(() => tmp.cleanup());

  const cached = ManifestBuilder();
  const uncached = ManifestBuilder(useCache: false);

  String cachePath() => tmp.resolve('.omnydrive/manifest-cache.json');

  Map<String, dynamic> readCache() =>
      jsonDecode(File(cachePath()).readAsStringSync()) as Map<String, dynamic>;

  /// Sets a file's mtime to a fixed instant safely in the past so the cache's
  /// racy-clean guard (mtime must be strictly older than the build time) does
  /// not force a re-hash.
  void backdate(String relative) {
    File(
      tmp.resolve(relative),
    ).setLastModifiedSync(DateTime(2020, 1, 1).toUtc());
  }

  /// Sets a file's mtime to a fixed future instant, i.e. never strictly older
  /// than a build time — so the racy-clean guard always distrusts it.
  void futuredate(String relative) {
    File(
      tmp.resolve(relative),
    ).setLastModifiedSync(DateTime(2999, 1, 1).toUtc());
  }

  test('warm-cache and non-cached builds produce identical hashes', () async {
    await tmp.writeFile('a.txt', 'alpha');
    await tmp.writeFile('sub/b.txt', 'beta');
    backdate('a.txt');
    backdate('sub/b.txt');

    final first = (await cached.build(tmp.path)).hash(); // writes cache
    backdate('a.txt'); // keep mtimes stable for the warm read
    backdate('sub/b.txt');
    final warm = (await cached.build(tmp.path)).hash(); // reads cache
    final plain = (await uncached.build(tmp.path)).hash();

    expect(warm, equals(first));
    expect(plain, equals(first));
  });

  test('changed content with advanced mtime is detected', () async {
    final f = await tmp.writeFile('a.txt', 'alpha');
    backdate('a.txt');
    final before = (await cached.build(tmp.path)).hash();

    await f.writeAsString('ALPHA-changed');
    // Leave the real (now) mtime, which is newer than the cached build.
    final after = (await cached.build(tmp.path)).hash();

    expect(after, isNot(equals(before)));
  });

  test('racy edit (mtime not older than build) is still re-hashed', () async {
    // The file's mtime sits at/after the cache build instant, so even though a
    // later same-size edit keeps an identical (size, mtime) fingerprint, the
    // racy-clean guard refuses to trust it.
    final f = await tmp.writeFile('a.txt', 'alpha');
    futuredate('a.txt');
    await cached.build(tmp.path); // caches mtime=2999, builtAt≈now

    await f.writeAsString('bravo'); // same 5-byte length as 'alpha'
    futuredate('a.txt'); // restore the cached mtime exactly

    final entry = (await cached.build(tmp.path)).entries['a.txt']!;
    final expected = (await uncached.build(tmp.path)).entries['a.txt']!;
    expect(entry.hash, equals(expected.hash)); // reflects 'bravo', not 'alpha'
  });

  test('additions appear and deletions drop from manifest and cache', () async {
    await tmp.writeFile('keep.txt', 'keep');
    await tmp.writeFile('drop.txt', 'drop');
    backdate('keep.txt');
    backdate('drop.txt');
    await cached.build(tmp.path);

    File(tmp.resolve('drop.txt')).deleteSync();
    await tmp.writeFile('new.txt', 'new');
    backdate('new.txt');
    final manifest = await cached.build(tmp.path);

    expect(manifest.entries.keys, containsAll(['keep.txt', 'new.txt']));
    expect(manifest.entries.containsKey('drop.txt'), isFalse);

    final entries = readCache()['entries'] as Map<String, dynamic>;
    expect(entries.keys, containsAll(['keep.txt', 'new.txt']));
    expect(entries.containsKey('drop.txt'), isFalse);
  });

  test(
    'corrupt or wrong-version cache falls back to a clean rebuild',
    () async {
      await tmp.writeFile('a.txt', 'alpha');
      backdate('a.txt');
      final expected = (await uncached.build(tmp.path)).hash();

      await tmp.writeFile('.omnydrive/manifest-cache.json', '{ not valid json');
      backdate('a.txt');
      expect((await cached.build(tmp.path)).hash(), equals(expected));

      await tmp.writeFile(
        '.omnydrive/manifest-cache.json',
        jsonEncode({'version': 999, 'entries': {}}),
      );
      backdate('a.txt');
      expect((await cached.build(tmp.path)).hash(), equals(expected));
    },
  );

  test('ignored directories never enter the manifest or cache', () async {
    await tmp.writeFile('a.txt', 'alpha');
    await tmp.writeFile('.git/config', 'gitstuff');
    await tmp.writeFile('.dart_tool/x', 'tool');
    backdate('a.txt');

    final manifest = await cached.build(tmp.path);
    expect(manifest.entries.keys, equals(['a.txt']));

    final entries = readCache()['entries'] as Map<String, dynamic>;
    expect(entries.keys, equals(['a.txt']));
  });
}
