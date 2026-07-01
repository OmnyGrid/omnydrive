import 'dart:convert';

import 'package:omnydrive/omnydrive.dart';
import 'package:test/test.dart';

void main() {
  group('GitPat', () {
    test('configArgs carry a base64 basic-auth header', () {
      final args = GitPat(token: 'secret-tok', username: 'alice').configArgs();
      expect(args[0], '-c');
      expect(args[1], startsWith('http.extraHeader=Authorization: Basic '));
      final b64 = args[1].split('Basic ').last;
      expect(utf8.decode(base64.decode(b64)), 'alice:secret-tok');
    });

    test('defaults the username when omitted', () {
      final args = GitPat(token: 't').configArgs();
      final b64 = args[1].split('Basic ').last;
      expect(utf8.decode(base64.decode(b64)), 'x-access-token:t');
    });

    test('has no environment overrides', () {
      expect(GitPat(token: 't').envVars(), isEmpty);
    });

    test('rejects an empty token', () {
      expect(() => GitPat(token: '  '), throwsA(isA<ValidationException>()));
    });

    test('masks the token in toString', () {
      final s = GitPat(token: 'hunter2', username: 'alice').toString();
      expect(s, contains('alice'));
      expect(s, isNot(contains('hunter2')));
      expect(s, contains('***'));
    });
  });

  group('GitUserPass', () {
    test('configArgs carry the base64 basic-auth header', () {
      final args = GitUserPass(username: 'bob', password: 'pw').configArgs();
      final b64 = args[1].split('Basic ').last;
      expect(utf8.decode(base64.decode(b64)), 'bob:pw');
    });

    test('requires username and password', () {
      expect(
        () => GitUserPass(username: '', password: 'p'),
        throwsA(isA<ValidationException>()),
      );
      expect(
        () => GitUserPass(username: 'u', password: ''),
        throwsA(isA<ValidationException>()),
      );
    });

    test('masks the password in toString', () {
      final s = GitUserPass(username: 'bob', password: 'sesame').toString();
      expect(s, contains('bob'));
      expect(s, isNot(contains('sesame')));
    });
  });

  group('GitSshKey', () {
    test('sets GIT_SSH_COMMAND with the key path and no config args', () {
      final cred = GitSshKey(keyPath: '/home/u/.ssh/id_ed25519');
      expect(cred.configArgs(), isEmpty);
      final cmd = cred.envVars()['GIT_SSH_COMMAND'];
      expect(cmd, contains('ssh -i /home/u/.ssh/id_ed25519'));
      expect(cmd, contains('IdentitiesOnly=yes'));
    });

    test('rejects an empty key path', () {
      expect(() => GitSshKey(keyPath: ''), throwsA(isA<ValidationException>()));
    });

    test('masks the passphrase in toString', () {
      final s = GitSshKey(keyPath: '/k', passphrase: 'topsecret').toString();
      expect(s, contains('/k'));
      expect(s, isNot(contains('topsecret')));
    });
  });

  group('GitCredential JSON round-trip', () {
    void roundTrips(GitCredential cred) {
      final restored = GitCredential.fromJson(cred.toJson());
      expect(restored.toJson(), cred.toJson());
      expect(restored.runtimeType, cred.runtimeType);
    }

    test('pat', () => roundTrips(GitPat(token: 't', username: 'a')));
    test(
      'userpass',
      () => roundTrips(GitUserPass(username: 'u', password: 'p')),
    );
    test('ssh', () => roundTrips(GitSshKey(keyPath: '/k', passphrase: 'x')));
    test('ssh without passphrase', () => roundTrips(GitSshKey(keyPath: '/k')));

    test('rejects an unknown kind', () {
      expect(
        () => GitCredential.fromJson({'kind': 'wat'}),
        throwsA(isA<InvalidJsonException>()),
      );
    });
  });

  group('OriginUri.host', () {
    test('extracts host from https and ssh urls', () {
      expect(OriginUri('https://github.com/org/repo.git').host, 'github.com');
      expect(OriginUri('ssh://git@gitlab.com/org/repo.git').host, 'gitlab.com');
      expect(OriginUri('git://example.org/repo.git').host, 'example.org');
    });

    test('extracts host from scp syntax', () {
      expect(OriginUri('git@github.com:org/repo.git').host, 'github.com');
    });

    test('is null for local dir and file origins', () {
      expect(OriginUri('/srv/data').host, isNull);
      expect(OriginUri('file:///srv/data').host, isNull);
    });
  });
}
