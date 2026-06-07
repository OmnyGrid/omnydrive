import 'package:omnydrive/omnydrive.dart';
import 'package:test/test.dart';

void main() {
  group('EndpointId', () {
    test('accepts slug-like values', () {
      expect(EndpointId('laptop-01').value, 'laptop-01');
    });
    test('rejects empty and invalid values', () {
      expect(() => EndpointId(''), throwsA(isA<ValidationException>()));
      expect(() => EndpointId('Bad Id'), throwsA(isA<ValidationException>()));
    });
    test('equality is by value', () {
      expect(EndpointId('a'), equals(EndpointId('a')));
    });
  });

  group('DriveId', () {
    test('scoped builds <endpoint>/<slug>', () {
      final id = DriveId.scoped(
        endpoint: EndpointId('nas'),
        name: 'My Project',
      );
      expect(id.value, 'nas/my-project');
      expect(id.endpoint, equals(EndpointId('nas')));
      expect(id.name, 'my-project');
    });
    test('rejects ids without an endpoint scope', () {
      expect(() => DriveId('justname'), throwsA(isA<ValidationException>()));
    });
  });

  group('LocalPath', () {
    test('requires absolute paths and normalizes', () {
      expect(LocalPath('/a/b/../c').value, '/a/c');
      expect(
        () => LocalPath('relative/x'),
        throwsA(isA<ValidationException>()),
      );
    });
  });

  group('OriginUri', () {
    test('classifies schemes', () {
      expect(OriginUri('/data/projects').scheme, OriginUriScheme.dir);
      expect(
        OriginUri('https://example.com/r.git').scheme,
        OriginUriScheme.https,
      );
      expect(
        OriginUri('git@github.com:org/repo.git').scheme,
        OriginUriScheme.ssh,
      );
      expect(OriginUri('https://example.com/r.git').isGitUrl, isTrue);
      expect(OriginUri('https://example.com/files').isRemote, isTrue);
      expect(OriginUri('/x').isRemote, isFalse);
    });
  });

  group('SyncRef', () {
    test('git and directory refs are distinct even with same value', () {
      expect(SyncRef.git('abc') == SyncRef.directory('abc'), isFalse);
      expect(SyncRef.git('abc'), equals(SyncRef.git('abc')));
    });
    test('round-trips through JSON', () {
      final ref = SyncRef.git('deadbeef');
      expect(SyncRef.fromJson(ref.toJson()), equals(ref));
    });
  });

  group('ContentHash', () {
    test('parses and serializes algo:hex', () {
      final h = ContentHash.parse('sha256:abcdef01');
      expect(h.algorithm, 'sha256');
      expect(h.hex, 'abcdef01');
      expect(h.value, 'sha256:abcdef01');
    });
    test('rejects non-hex', () {
      expect(
        () => ContentHash(hex: 'xyz'),
        throwsA(isA<ValidationException>()),
      );
    });
  });

  group('BranchName', () {
    test('detects protected branches', () {
      expect(BranchName('main').isProtected(), isTrue);
      expect(BranchName('omnydrive/update-1').isProtected(), isFalse);
    });
    test('rejects invalid names', () {
      expect(() => BranchName('bad name'), throwsA(isA<ValidationException>()));
      expect(() => BranchName('a..b'), throwsA(isA<ValidationException>()));
    });
  });

  group('CapabilitySet', () {
    test('intersect and json round-trip', () {
      final a = CapabilitySet([
        Capability.read,
        Capability.write,
        Capability.push,
      ]);
      final b = CapabilitySet([Capability.read, Capability.push]);
      expect(a.intersect(b).values, {Capability.read, Capability.push});
      expect(CapabilitySet.fromJson(a.toJson()), equals(a));
    });
  });

  group('AuthToken', () {
    test('hides its value in toString', () {
      expect(AuthToken('secret').toString(), isNot(contains('secret')));
    });
  });
}
