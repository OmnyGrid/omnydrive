import 'dart:io';

import 'package:path/path.dart' as p;

/// Light, fast, transport-agnostic compression policy for drive content.
///
/// Uses gzip (default level **4** — its ratio is within a hair of the default
/// level 6 while compressing markedly faster) to shrink file pulls, file pushes
/// and manifest payloads. The built-in HTTP transport
/// ([ContentServer]/[HttpContentSource]) applies it automatically, negotiated
/// with the standard `Accept-Encoding` / `Content-Encoding` headers.
///
/// Two payloads are sent verbatim instead:
///  * anything below [minBytes] — gzip's framing overhead can make tiny files
///    *larger*, and the CPU is wasted; and
///  * already-compressed file types ([skipExtensions]) — re-gzipping a JPEG or a
///    zip buys nothing.
///
/// The policy is configurable and injectable: pass a custom instance to
/// [ContentServer], [HttpContentSource], `networkedProviderRegistry` or
/// [OmnyClient] to tune the gzip [level], the [minBytes] threshold or the
/// [skipExtensions] set, or use [ContentCompression.disabled] to turn it off.
///
/// ## Custom transports
///
/// This type has no HTTP dependency, so a custom [ContentSource] over a
/// non-HTTP channel can reuse it directly. Compress at the **sending** edge and
/// decompress at the **receiving** edge of the transport (mirroring what the
/// HTTP layer does internally):
///
/// ```dart
/// final gz = ContentCompression.standard;
///
/// // sending side (e.g. an RPC write request):
/// final compress = gz.shouldCompress(path, bytes.length);
/// final payload = compress ? gz.encode(bytes) : bytes;
/// send(path, payload, gzip: compress); // carry the flag however the protocol allows
///
/// // receiving side:
/// final bytes = ContentCompression.looksGzipped(payload)
///     ? ContentCompression.decode(payload)
///     : payload;
/// ```
class ContentCompression {
  /// Default gzip level: fast, with a ratio close to the level-6 default.
  static const int defaultLevel = 4;

  /// Default minimum payload size (bytes) below which nothing is compressed.
  static const int defaultMinBytes = 1024;

  /// Extensions whose contents are already compressed; re-gzipping wastes CPU
  /// for ~no size win, so they are sent as-is by [standard].
  static const Set<String> defaultSkipExtensions = {
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

  /// The default policy used when none is injected.
  static final ContentCompression standard = ContentCompression();

  /// A policy that compresses nothing — every payload is sent verbatim.
  static final ContentCompression disabled = ContentCompression(enabled: false);

  /// Whether this policy compresses at all. When `false`, [shouldCompress] and
  /// [shouldCompressBytes] always return `false`.
  final bool enabled;

  /// The gzip compression level used by [encode].
  final int level;

  /// Payloads smaller than this (in bytes) are left uncompressed.
  final int minBytes;

  /// Extensions (without the leading dot, lower-case) treated as already
  /// compressed and skipped by [shouldCompress].
  final Set<String> skipExtensions;

  final GZipCodec _codec;

  /// Creates a compression policy. All parameters default to the standard
  /// values ([defaultLevel], [defaultMinBytes], [defaultSkipExtensions]).
  ContentCompression({
    this.enabled = true,
    this.level = defaultLevel,
    this.minBytes = defaultMinBytes,
    Set<String>? skipExtensions,
  }) : skipExtensions = skipExtensions ?? defaultSkipExtensions,
       _codec = GZipCodec(level: level);

  /// Whether a payload of [byteLength] bytes located at [path] is worth gzipping
  /// under this policy.
  bool shouldCompress(String path, int byteLength) {
    if (!enabled || byteLength < minBytes) return false;
    final ext = p.extension(path).toLowerCase();
    return ext.isEmpty || !skipExtensions.contains(ext.substring(1));
  }

  /// Whether a size-[byteLength] payload with no meaningful extension (e.g. the
  /// JSON manifest) is worth gzipping. Gated on [enabled] and size only.
  bool shouldCompressBytes(int byteLength) => enabled && byteLength >= minBytes;

  /// Gzip-encodes [bytes] at this policy's [level].
  List<int> encode(List<int> bytes) => _codec.encode(bytes);

  /// Gunzips [bytes]. Level-agnostic, so it decodes any gzip stream regardless
  /// of the level it was produced with.
  static List<int> decode(List<int> bytes) => gzip.decode(bytes);

  /// Whether [bytes] begin with the gzip magic number (`0x1f 0x8b`), i.e. they
  /// are an actual gzip stream rather than already-decoded content. Lets a
  /// receiver decode safely even when an upstream HTTP client may have already
  /// transparently uncompressed the body.
  static bool looksGzipped(List<int> bytes) =>
      bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b;

  /// Whether an `Accept-Encoding` header value advertises gzip support.
  static bool acceptsGzip(String? acceptEncoding) =>
      acceptEncoding != null && acceptEncoding.toLowerCase().contains('gzip');

  /// Whether a `Content-Encoding` header value marks the body as gzip-encoded.
  static bool isGzip(String? contentEncoding) =>
      contentEncoding != null && contentEncoding.toLowerCase().contains('gzip');
}
