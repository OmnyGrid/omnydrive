import 'dart:io';

import 'package:path/path.dart' as p;

/// Light, fast transparent compression for the directory-drive content
/// transport.
///
/// Uses gzip **level 4** — its ratio is within a hair of the default level 6
/// while compressing markedly faster — to shrink file pulls, file pushes and
/// manifest payloads over HTTP. Negotiation rides the standard `Accept-Encoding`
/// / `Content-Encoding` headers, so it stays correct whether or not the peer's
/// HTTP client transparently uncompresses the body.
///
/// Two payloads are sent verbatim instead:
///  * anything below [minBytes] — gzip's framing overhead can make tiny files
///    *larger*, and the CPU is wasted; and
///  * already-compressed file types ([_incompressible]) — re-gzipping a JPEG or
///    a zip buys nothing.
class ContentCompression {
  ContentCompression._();

  static final GZipCodec _gzip = GZipCodec(level: 4); // fast, ~level-6 ratio.

  /// Payloads smaller than this (in bytes) are transferred uncompressed.
  static const int minBytes = 1024;

  /// Extensions whose contents are already compressed; re-gzipping wastes CPU
  /// for ~no size win, so they are sent as-is.
  static const Set<String> _incompressible = {
    // images
    'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'heif', 'avif', 'jp2',
    // video
    'mp4', 'm4v', 'mkv', 'mov', 'avi', 'webm', 'flv', 'wmv', 'mpg', 'mpeg',
    // audio
    'mp3', 'aac', 'ogg', 'oga', 'opus', 'flac', 'm4a', 'wma',
    // archives / already-compressed containers
    'zip', 'gz', 'tgz', 'bz2', 'tbz2', 'xz', 'txz', '7z', 'rar', 'zst', 'br',
    'lz4', 'lzma', 'cab', 'arj',
    // documents (zip-based) & pdf
    'pdf', 'docx', 'xlsx', 'pptx', 'odt', 'ods', 'odp', 'epub',
    // other
    'apk', 'jar', 'war', 'wasm', 'woff', 'woff2', 'dmg', 'iso', 'crx',
  };

  /// Whether a payload of [byteLength] bytes located at [path] is worth gzipping.
  static bool shouldCompress(String path, int byteLength) {
    if (byteLength < minBytes) return false;
    final ext = p.extension(path).toLowerCase();
    return ext.isEmpty || !_incompressible.contains(ext.substring(1));
  }

  /// Whether a size-[byteLength] payload with no meaningful extension (e.g. the
  /// JSON manifest) is worth gzipping. Gated on size only.
  static bool shouldCompressBytes(int byteLength) => byteLength >= minBytes;

  /// Whether an `Accept-Encoding` header advertises gzip support.
  static bool acceptsGzip(String? acceptEncoding) =>
      acceptEncoding != null && acceptEncoding.toLowerCase().contains('gzip');

  /// Whether a `Content-Encoding` header marks the body as gzip-encoded.
  static bool isGzip(String? contentEncoding) =>
      contentEncoding != null && contentEncoding.toLowerCase().contains('gzip');

  /// Gzip-encodes [bytes] at level 4.
  static List<int> encode(List<int> bytes) => _gzip.encode(bytes);

  /// Gunzips [bytes]. Level-agnostic, so it decodes any gzip stream.
  static List<int> decode(List<int> bytes) => gzip.decode(bytes);
}
