import 'dart:io';

import 'package:omnydrive/omnydrive.dart'
    show
        ContentServer,
        FileDriveRegistry,
        FileMountRegistry,
        HubServer,
        LocalDriveHub;
import 'package:omnydrive/omnydrive_cli.dart';
import 'package:omnyhub/omnyhub.dart' show OmnyHub;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../support/temp_dir.dart';

void main() {
  late OmnyHub hubHttp;
  late OmnyHub contentHttp;
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
    await hubHttp.stop();
    await contentHttp.stop();
    await stateA.cleanup();
    await stateB.cleanup();
  });

  Future<int> cli(String state, List<String> args) =>
      runOmnydrive(['--state', state, ...args]);

  // Logs in both endpoints, publishes a seeded directory and clones it,
  // returning the origin dir, the mirror path and the persisted mount id.
  Future<({TempDir src, String dest, String mountId})> setup(
    Map<String, String> seed,
  ) async {
    await cli(stateA.path, [
      'login',
      '--hub',
      hubUrl,
      '--id',
      'alpha',
      '--serve-url',
      contentUrl,
    ]);
    final src = await TempDir.create('omnydrive_cli_src_');
    addTearDown(src.cleanup);
    for (final entry in seed.entries) {
      await src.writeFile(entry.key, entry.value);
    }
    await cli(stateA.path, ['publish', src.path, '--name', 'docs']);

    await cli(stateB.path, [
      'login',
      '--hub',
      hubUrl,
      '--id',
      'beta',
      '--serve-url',
      'http://beta.invalid',
    ]);
    final dst = await TempDir.create('omnydrive_cli_dst_');
    addTearDown(dst.cleanup);
    final dest = p.join(dst.path, 'm');
    await cli(stateB.path, ['clone', 'alpha/docs', dest]);

    final mounts = await FileMountRegistry(
      p.join(stateB.path, 'mounts.json'),
    ).findAll();
    return (src: src, dest: dest, mountId: mounts.single.id.value);
  }

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

  test('sync pulls origin changes via the CLI', () async {
    final s = await setup({'readme.md': 'hello'});

    // The origin moves after the clone; the mount is otherwise untouched.
    await s.src.writeFile('readme.md', 'updated');
    await s.src.writeFile('extra.txt', 'X');

    expect(await cli(stateB.path, ['sync', s.mountId]), 0);
    expect(File(p.join(s.dest, 'readme.md')).readAsStringSync(), 'updated');
    expect(File(p.join(s.dest, 'extra.txt')).readAsStringSync(), 'X');
  });

  test('sync reports a conflict (exit 6) without losing data', () async {
    final s = await setup({'f.txt': 'base'});

    // Both sides diverge from the baseline.
    await s.src.writeFile('f.txt', 'origin-change');
    await File(p.join(s.dest, 'f.txt')).writeAsString('local-change');

    expect(await cli(stateB.path, ['sync', s.mountId]), 6);
    // Neither side is clobbered by the refused sync.
    expect(
      File(p.join(s.src.path, 'f.txt')).readAsStringSync(),
      'origin-change',
    );
    expect(File(p.join(s.dest, 'f.txt')).readAsStringSync(), 'local-change');
  });

  test('publish --exclude is honored end-to-end over HTTP', () async {
    await cli(stateA.path, [
      'login',
      '--hub',
      hubUrl,
      '--id',
      'alpha',
      '--serve-url',
      contentUrl,
    ]);

    final src = await TempDir.create('omnydrive_cli_src_');
    addTearDown(src.cleanup);
    await src.writeFile('keep.txt', 'K');
    await src.writeFile('secret/p.txt', 'P');

    expect(
      await cli(stateA.path, [
        'publish',
        src.path,
        '--name',
        'docs',
        '--exclude',
        'secret/**',
      ]),
      0,
    );

    await cli(stateB.path, [
      'login',
      '--hub',
      hubUrl,
      '--id',
      'beta',
      '--serve-url',
      'http://beta.invalid',
    ]);
    final dest = p.join((await TempDir.create('omnydrive_cli_dst_')).path, 'm');
    addTearDown(() => Directory(dest).parent.delete(recursive: true));

    expect(await cli(stateB.path, ['clone', 'alpha/docs', dest]), 0);
    // The whitelisted file is mirrored; the excluded sub-path never crosses
    // the HTTP content server.
    expect(File(p.join(dest, 'keep.txt')).readAsStringSync(), 'K');
    expect(File(p.join(dest, 'secret/p.txt')).existsSync(), isFalse);
  });

  test('publish --exclude with --git is rejected (exit 1)', () async {
    await cli(stateA.path, [
      'login',
      '--hub',
      hubUrl,
      '--id',
      'alpha',
      '--serve-url',
      contentUrl,
    ]);
    expect(
      await cli(stateA.path, [
        'publish',
        'https://example.com/repo.git',
        '--git',
        '--exclude',
        'x/**',
      ]),
      1,
    );
  });

  test(
    '.omnyignore supplies default excludes when no flags are given',
    () async {
      await cli(stateA.path, [
        'login',
        '--hub',
        hubUrl,
        '--id',
        'alpha',
        '--serve-url',
        contentUrl,
      ]);

      final src = await TempDir.create('omnydrive_cli_src_');
      addTearDown(src.cleanup);
      await src.writeFile('keep.txt', 'K');
      await src.writeFile('secret/p.txt', 'P');
      await src.writeFile('.omnyignore', '# defaults\nsecret/**\n');

      // No --include/--exclude: the ignore file drives the filter.
      expect(
        await cli(stateA.path, ['publish', src.path, '--name', 'docs']),
        0,
      );

      await cli(stateB.path, [
        'login',
        '--hub',
        hubUrl,
        '--id',
        'beta',
        '--serve-url',
        'http://beta.invalid',
      ]);
      final dest = p.join(
        (await TempDir.create('omnydrive_cli_dst_')).path,
        'm',
      );
      addTearDown(() => Directory(dest).parent.delete(recursive: true));

      expect(await cli(stateB.path, ['clone', 'alpha/docs', dest]), 0);
      expect(File(p.join(dest, 'keep.txt')).readAsStringSync(), 'K');
      expect(File(p.join(dest, 'secret/p.txt')).existsSync(), isFalse);
    },
  );

  test('explicit --include overrides the .omnyignore file', () async {
    await cli(stateA.path, [
      'login',
      '--hub',
      hubUrl,
      '--id',
      'alpha',
      '--serve-url',
      contentUrl,
    ]);

    final src = await TempDir.create('omnydrive_cli_src_');
    addTearDown(src.cleanup);
    await src.writeFile('secret/p.txt', 'P');
    // The ignore file would drop secret/**, but an explicit --include wins and
    // skips the file entirely.
    await src.writeFile('.omnyignore', 'secret/**\n');

    expect(
      await cli(stateA.path, [
        'publish',
        src.path,
        '--name',
        'docs',
        '--include',
        'secret/**',
      ]),
      0,
    );

    await cli(stateB.path, [
      'login',
      '--hub',
      hubUrl,
      '--id',
      'beta',
      '--serve-url',
      'http://beta.invalid',
    ]);
    final dest = p.join((await TempDir.create('omnydrive_cli_dst_')).path, 'm');
    addTearDown(() => Directory(dest).parent.delete(recursive: true));

    expect(await cli(stateB.path, ['clone', 'alpha/docs', dest]), 0);
    expect(File(p.join(dest, 'secret/p.txt')).readAsStringSync(), 'P');
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
