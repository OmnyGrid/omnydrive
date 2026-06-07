// Demonstrates the consumer side: once drives are published, a process that only
// imports `package:omnydrive/omnydrive_client.dart` can discover them and read
// their content through OmnyClient — no engine, providers or servers required.
//
// Run with: dart run example/client_sdk.dart

import 'dart:io';

import 'package:omnydrive/omnydrive_client.dart';

import 'scenario.dart';

Future<void> main() async {
  final s = await Scenario.start();
  try {
    // --- Server side: publish a couple of directory drives -----------------
    final alpha = await s.publisher('alpha');

    final docs = s.dir('docs');
    File('$docs/readme.md').writeAsStringSync('hello\n');
    File('$docs/guide.md').writeAsStringSync('a short guide\n');
    await alpha.publishDirectory(path: docs, name: 'docs');

    final media = s.dir('media');
    File('$media/note.txt').writeAsStringSync('a media note\n');
    await alpha.publishDirectory(path: media, name: 'media');

    // --- Client side: browse purely through the SDK ------------------------
    final client = OmnyClient(s.hubUrl);
    try {
      final drives = await client.drives();
      print('${drives.length} drive(s) on the hub:\n');
      for (final reg in drives) {
        final content = client.content(reg);
        final manifest = await content.manifest();
        print('${reg.id}  (${manifest.entries.length} file(s))');
        for (final path in manifest.sortedPaths) {
          final bytes = await content.readBytes(path);
          print('  $path -> ${String.fromCharCodes(bytes).trim()}');
        }
      }
    } finally {
      client.close();
    }
  } finally {
    await s.stop();
  }
}
