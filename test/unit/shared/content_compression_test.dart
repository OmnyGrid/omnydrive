import 'dart:convert';

import 'package:omnydrive/omnydrive.dart';
import 'package:test/test.dart';

void main() {
  group('ContentCompression.shouldCompress', () {
    test('skips payloads below the minimum size', () {
      expect(ContentCompression.shouldCompress('a.txt', 10), isFalse);
      expect(
        ContentCompression.shouldCompress(
          'a.txt',
          ContentCompression.minBytes - 1,
        ),
        isFalse,
      );
      expect(
        ContentCompression.shouldCompress('a.txt', ContentCompression.minBytes),
        isTrue,
      );
    });

    test('compresses text and extensionless files above the threshold', () {
      const big = ContentCompression.minBytes + 1;
      expect(ContentCompression.shouldCompress('notes.txt', big), isTrue);
      expect(ContentCompression.shouldCompress('README.md', big), isTrue);
      expect(ContentCompression.shouldCompress('data.json', big), isTrue);
      expect(ContentCompression.shouldCompress('LICENSE', big), isTrue);
    });

    test('skips already-compressed file types regardless of size', () {
      const big = ContentCompression.minBytes * 100;
      for (final name in [
        'photo.jpg',
        'clip.MP4',
        'bundle.zip',
        'doc.pdf',
        'lib.wasm',
      ]) {
        expect(
          ContentCompression.shouldCompress(name, big),
          isFalse,
          reason: name,
        );
      }
    });
  });

  group('ContentCompression header helpers', () {
    test('acceptsGzip / isGzip read their headers case-insensitively', () {
      expect(ContentCompression.acceptsGzip('gzip, deflate, br'), isTrue);
      expect(ContentCompression.acceptsGzip('GZIP'), isTrue);
      expect(ContentCompression.acceptsGzip('identity'), isFalse);
      expect(ContentCompression.acceptsGzip(null), isFalse);

      expect(ContentCompression.isGzip('gzip'), isTrue);
      expect(ContentCompression.isGzip(null), isFalse);
      expect(ContentCompression.isGzip('identity'), isFalse);
    });
  });

  group('ContentCompression encode/decode', () {
    test('round-trips bytes and actually shrinks compressible data', () {
      final original = utf8.encode('omnydrive ' * 500); // highly repetitive
      final encoded = ContentCompression.encode(original);
      expect(encoded.length, lessThan(original.length));
      expect(ContentCompression.decode(encoded), equals(original));
    });
  });
}
