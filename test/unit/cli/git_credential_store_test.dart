import 'package:omnydrive/omnydrive.dart';
import 'package:test/test.dart';

import '../../support/temp_dir.dart';

void main() {
  group('GitCredentialStore', () {
    test('put/get/remove by host', () {
      final store = GitCredentialStore();
      expect(store.get('github.com'), isNull);

      store.put('github.com', GitPat(token: 't'));
      expect(store.get('github.com'), isA<GitPat>());
      expect(store.hosts, ['github.com']);

      expect(store.remove('github.com'), isTrue);
      expect(store.remove('github.com'), isFalse);
      expect(store.get('github.com'), isNull);
    });

    test('resolve keys off the origin host', () {
      final store = GitCredentialStore()..put('github.com', GitPat(token: 't'));

      expect(
        store.resolve(OriginUri('https://github.com/org/repo.git')),
        isA<GitPat>(),
      );
      expect(
        store.resolve(OriginUri('git@github.com:org/repo.git')),
        isA<GitPat>(),
      );
      // Different host -> no credential.
      expect(
        store.resolve(OriginUri('https://gitlab.com/org/repo.git')),
        isNull,
      );
      // Local origin has no host -> no credential.
      expect(store.resolve(OriginUri('/srv/data')), isNull);
    });

    test('save then load round-trips all variants', () async {
      final dir = await TempDir.create();
      addTearDown(dir.cleanup);

      final store = GitCredentialStore()
        ..put('github.com', GitPat(token: 'tok', username: 'me'))
        ..put('example.com', GitUserPass(username: 'u', password: 'p'))
        ..put('git.internal', GitSshKey(keyPath: '/k', passphrase: 'x'));
      await store.save(dir.path);

      final loaded = await GitCredentialStore.load(dir.path);
      expect(loaded.hosts.toSet(), {
        'github.com',
        'example.com',
        'git.internal',
      });
      expect(
        loaded.get('github.com')!.toJson(),
        GitPat(token: 'tok', username: 'me').toJson(),
      );
      expect(loaded.get('example.com'), isA<GitUserPass>());
      expect(loaded.get('git.internal'), isA<GitSshKey>());
    });

    test('load returns an empty store when no file exists', () async {
      final dir = await TempDir.create();
      addTearDown(dir.cleanup);
      final store = await GitCredentialStore.load(dir.path);
      expect(store.hosts, isEmpty);
    });
  });
}
