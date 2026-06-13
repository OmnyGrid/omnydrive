@TestOn('!windows')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:omnydrive/omnydrive.dart';
import 'package:test/test.dart';

import '../../support/temp_dir.dart';

/// Whether the file at [path] carries any POSIX execute bit.
bool isExecutable(String path) => (File(path).statSync().mode & 0x49) != 0;

void main() {
  late TempDir tmp;

  setUp(() async {
    tmp = await TempDir.create('omnydrive_exec_');
  });
  tearDown(() => tmp.cleanup());

  group('ManifestBuilder', () {
    test('captures the executable bit from disk', () async {
      await tmp.writeFile('run.sh', '#!/bin/sh\necho hi\n');
      await tmp.writeFile('plain.txt', 'data');
      await Process.run('chmod', ['+x', tmp.resolve('run.sh')]);

      final manifest = await const ManifestBuilder(
        useCache: false,
      ).build(tmp.path);

      expect(manifest.entries['run.sh']!.executable, isTrue);
      expect(manifest.entries['plain.txt']!.executable, isFalse);
    });
  });

  group('LocalContentSource', () {
    ContentHash hashOf(List<int> bytes) =>
        ContentHash(hex: sha256.convert(bytes).toString());

    test('writeBytes(executable: true) sets +x; false leaves it off', () async {
      final source = LocalContentSource(tmp.path);
      final bytes = utf8.encode('#!/bin/sh\necho ok\n');

      await source.writeBytes('a/run.sh', bytes, executable: true);
      await source.writeBytes('a/plain.txt', bytes);

      expect(isExecutable(tmp.resolve('a/run.sh')), isTrue);
      expect(isExecutable(tmp.resolve('a/plain.txt')), isFalse);
    });

    test('writeBytes preserves +x on the streaming (progress) path', () async {
      final source = LocalContentSource(tmp.path);
      final bytes = utf8.encode('#!/bin/sh\nstreamed\n');

      await source.writeBytes(
        'run.sh',
        bytes,
        executable: true,
        onProgress: (sent, total) {},
      );

      expect(isExecutable(tmp.resolve('run.sh')), isTrue);
    });

    test('copy(executable: true) sets +x on the destination', () async {
      final source = LocalContentSource(tmp.path);
      final bytes = utf8.encode('#!/bin/sh\ncopied\n');
      await source.writeBytes('src.sh', bytes, executable: true);

      final copied = await source.copy(
        'src.sh',
        'dst.sh',
        hashOf(bytes),
        executable: true,
      );

      expect(copied, isTrue);
      expect(isExecutable(tmp.resolve('dst.sh')), isTrue);
    });
  });
}
