import 'dart:io';

import 'package:omnydrive/omnydrive.dart'
    show
        ContentServer,
        FileDriveRegistry,
        FileMountRegistry,
        HubServer,
        LocalDriveHub;
import 'package:omnydrive/omnydrive_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../support/temp_dir.dart';

void main() {
  late HttpServer hubHttp;
  late HttpServer contentHttp;
  late String hubUrl;
  late String contentUrl;
  late TempDir stateA; // publisher
  late TempDir stateB; // cloner

  setUp(() async {
    hubHttp = await HubServer(
      LocalDriveHub(),
    ).serve(address: '127.0.0.1', port: 0);
    hubUrl = 'http://127.0.0.1:${hubHttp.port}';

    stateA = await TempDir.create('omnydrive_cli_a_');
    stateB = await TempDir.create('omnydrive_cli_b_');

    // Content server reads the publisher endpoint's file-backed drive registry,
    // exactly as `omnydrive serve-content` does.
    contentHttp = await ContentServer(
      FileDriveRegistry(p.join(stateA.path, 'drives.json')),
    ).serve(address: '127.0.0.1', port: 0);
    contentUrl = 'http://127.0.0.1:${contentHttp.port}';
  });

  tearDown(() async {
    await hubHttp.close(force: true);
    await contentHttp.close(force: true);
    await stateA.cleanup();
    await stateB.cleanup();
  });

  Future<int> cli(String state, List<String> args) =>
      runOmnydrive(['--state', state, ...args]);

  test('full publish / clone / sync round-trip via the CLI', () async {
    // Publisher logs in and publishes a directory.
    expect(
      await cli(stateA.path, [
        'login',
        '--hub',
        hubUrl,
        '--id',
        'alpha',
        '--serve-url',
        contentUrl,
      ]),
      0,
    );

    final src = await TempDir.create('omnydrive_cli_src_');
    addTearDown(src.cleanup);
    await src.writeFile('readme.md', 'hello');
    await src.writeFile('docs/a.txt', 'A');

    expect(await cli(stateA.path, ['publish', src.path, '--name', 'docs']), 0);

    // Cloner logs in, clones, edits and syncs back.
    expect(
      await cli(stateB.path, [
        'login',
        '--hub',
        hubUrl,
        '--id',
        'beta',
        '--serve-url',
        'http://beta.invalid',
      ]),
      0,
    );

    final dest = p.join((await TempDir.create('omnydrive_cli_dst_')).path, 'm');
    addTearDown(() => Directory(dest).parent.delete(recursive: true));

    expect(await cli(stateB.path, ['clone', 'alpha/docs', dest]), 0);
    expect(File(p.join(dest, 'readme.md')).readAsStringSync(), 'hello');
    expect(File(p.join(dest, 'docs/a.txt')).readAsStringSync(), 'A');

    // Find the mount id the CLI persisted.
    final mounts = await FileMountRegistry(
      p.join(stateB.path, 'mounts.json'),
    ).findAll();
    expect(mounts, hasLength(1));
    final mountId = mounts.single.id.value;

    await File(p.join(dest, 'readme.md')).writeAsString('hello world');
    expect(await cli(stateB.path, ['sync', mountId]), 0);
    expect(
      File(p.join(src.path, 'readme.md')).readAsStringSync(),
      'hello world',
    );
  });

  test('commands without a login fail with exit code 1', () async {
    final empty = await TempDir.create('omnydrive_cli_empty_');
    addTearDown(empty.cleanup);
    expect(await cli(empty.path, ['drives']), 1);
  });

  test('unknown command yields a usage error (exit 64)', () async {
    expect(await runOmnydrive(['frobnicate']), 64);
  });
}
