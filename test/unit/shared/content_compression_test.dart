import 'dart:convert';

import 'package:omnydrive/omnydrive.dart';
import 'package:test/test.dart';

void main() {
  final gz = ContentCompression.standard;

  group('ContentCompression.standard.shouldCompress', () {
    test('skips payloads below the minimum size', () {
      expect(gz.shouldCompress('a.txt', 10), isFalse);
      expect(gz.shouldCompress('a.txt', gz.minBytes - 1), isFalse);
      expect(gz.shouldCompress('a.txt', gz.minBytes), isTrue);
    });

    test('compresses text and extensionless files above the threshold', () {
      final big = gz.minBytes + 1;
      expect(gz.shouldCompress('notes.txt', big), isTrue);
      expect(gz.shouldCompress('README.md', big), isTrue);
      expect(gz.shouldCompress('data.json', big), isTrue);
      expect(gz.shouldCompress('LICENSE', big), isTrue);
    });

    test('skips already-compressed file types regardless of size', () {
      final big = gz.minBytes * 100;
      for (final name in [
        'photo.jpg',
        'clip.MP4',
        'bundle.zip',
        'doc.pdf',
        'lib.wasm',
      ]) {
        expect(gz.shouldCompress(name, big), isFalse, reason: name);
      }
    });
  });

  group('configurable policy', () {
    test('a custom minBytes and skip-extension set are honored', () {
      final policy = ContentCompression(minBytes: 16, skipExtensions: {'log'});
      expect(
        policy.shouldCompress('tiny.txt', 16),
        isTrue,
      ); // below default 1KiB
      expect(policy.shouldCompress('tiny.txt', 15), isFalse);
      expect(policy.shouldCompress('app.log', 1000), isFalse); // custom skip
      expect(
        policy.shouldCompress('photo.jpg', 1000),
        isTrue,
      ); // not in custom set
    });

    test('a custom level still round-trips and changes output size', () {
      final original = utf8.encode('omnydrive ' * 500);
      final fast = ContentCompression(level: 1).encode(original);
      final best = ContentCompression(level: 9).encode(original);
      expect(ContentCompression.decode(fast), equals(original));
      expect(ContentCompression.decode(best), equals(original));
      expect(best.length, lessThanOrEqualTo(fast.length));
    });

    test('the disabled policy never compresses', () {
      final off = ContentCompression.disabled;
      expect(off.enabled, isFalse);
      expect(off.shouldCompress('big.txt', 1 << 20), isFalse);
      expect(off.shouldCompressBytes(1 << 20), isFalse);
    });
  });

  group('static helpers', () {
    test('acceptsGzip / isGzip read headers case-insensitively', () {
      expect(ContentCompression.acceptsGzip('gzip, deflate, br'), isTrue);
      expect(ContentCompression.acceptsGzip('GZIP'), isTrue);
      expect(ContentCompression.acceptsGzip('identity'), isFalse);
      expect(ContentCompression.acceptsGzip(null), isFalse);

      expect(ContentCompression.isGzip('gzip'), isTrue);
      expect(ContentCompression.isGzip(null), isFalse);
      expect(ContentCompression.isGzip('identity'), isFalse);
    });

    test('looksGzipped detects the gzip magic number', () {
      final encoded = gz.encode(utf8.encode('hello ' * 200));
      expect(ContentCompression.looksGzipped(encoded), isTrue);
      expect(
        ContentCompression.looksGzipped(utf8.encode('plain text')),
        isFalse,
      );
      expect(
        ContentCompression.looksGzipped(const [0x1f]),
        isFalse,
      ); // too short
    });

    test('decode reverses encode regardless of level (level-agnostic)', () {
      final original = utf8.encode('omnydrive ' * 500);
      final encoded = ContentCompression(level: 4).encode(original);
      expect(encoded.length, lessThan(original.length));
      expect(ContentCompression.decode(encoded), equals(original));
    });
  });
}
