import 'package:omnydrive/omnydrive.dart';
import 'package:test/test.dart';

void main() {
  test('an empty filter keeps every path', () {
    final filter = PathFilter();
    expect(filter.isEmpty, isTrue);
    expect(filter.matches('anything/at/all.txt'), isTrue);
    expect(PathFilter.empty.matches('x'), isTrue);
  });

  test('exclude drops matching paths and wins over include', () {
    final filter = PathFilter(include: ['**'], exclude: ['secret/**']);
    expect(filter.matches('docs/a.txt'), isTrue);
    expect(filter.matches('secret/p.txt'), isFalse);
    expect(filter.matches('secret/deep/p.txt'), isFalse);
  });

  test('include acts as a whitelist when present', () {
    final filter = PathFilter(include: ['src/**']);
    expect(filter.matches('src/main.dart'), isTrue);
    expect(filter.matches('src/a/b.dart'), isTrue);
    expect(filter.matches('test/main_test.dart'), isFalse);
    expect(filter.matches('readme.md'), isFalse);
  });

  test('single star does not cross a path separator', () {
    final filter = PathFilter(include: ['*.tmp']);
    expect(filter.matches('a.tmp'), isTrue);
    expect(filter.matches('sub/a.tmp'), isFalse);
  });

  test('double star crosses separators', () {
    final filter = PathFilter(include: ['logs/**']);
    expect(filter.matches('logs/a.log'), isTrue);
    expect(filter.matches('logs/deep/a.log'), isTrue);
    expect(filter.matches('other/a.log'), isFalse);
  });

  test('question mark matches a single non-separator character', () {
    final filter = PathFilter(include: ['file?.txt']);
    expect(filter.matches('file1.txt'), isTrue);
    expect(filter.matches('file12.txt'), isFalse);
    expect(filter.matches('file/.txt'), isFalse);
  });

  test('a trailing-slash or bare directory token matches the subtree', () {
    final slash = PathFilter(exclude: ['build/']);
    expect(slash.matches('build/app.js'), isFalse);
    expect(slash.matches('build/x/y.js'), isFalse);
    expect(slash.matches('src/build.dart'), isTrue);

    final bare = PathFilter(exclude: ['node_modules']);
    expect(bare.matches('node_modules/pkg/index.js'), isFalse);
    expect(bare.matches('src/node_modules_helper.dart'), isTrue);
  });

  test('a leading slash anchors to the root and is insignificant', () {
    final filter = PathFilter(include: ['/src/**']);
    expect(filter.matches('src/main.dart'), isTrue);
    expect(filter.matches('/src/main.dart'), isTrue);
    expect(filter.matches('vendor/src/main.dart'), isFalse);
  });

  test('regex metacharacters in patterns are matched literally', () {
    final filter = PathFilter(include: ['a.(b)+/x.txt']);
    expect(filter.matches('a.(b)+/x.txt'), isTrue);
    expect(filter.matches('axxbbb/x.txt'), isFalse);
  });

  test('an empty pattern is rejected', () {
    expect(
      () => PathFilter(include: ['']),
      throwsA(isA<ValidationException>()),
    );
    expect(
      () => PathFilter(exclude: ['  ']),
      throwsA(isA<ValidationException>()),
    );
  });

  test('round-trips through JSON and compares by value', () {
    final filter = PathFilter(include: ['src/**'], exclude: ['**/*.tmp']);
    final restored = PathFilter.fromJson(filter.toJson());
    expect(restored, filter);
    expect(restored.hashCode, filter.hashCode);
    expect(restored.matches('src/main.dart'), isTrue);
    expect(restored.matches('src/cache.tmp'), isFalse);
  });

  test('empty filter serializes to an empty map', () {
    expect(PathFilter().toJson(), isEmpty);
    expect(PathFilter.fromJson(const {}).isEmpty, isTrue);
  });
}
