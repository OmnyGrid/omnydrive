import 'package:omnydrive/omnydrive.dart';
import 'package:test/test.dart';

void main() {
  test('ProviderType wire round-trip', () {
    for (final v in ProviderType.values) {
      expect(ProviderType.fromWire(v.wireValue), v);
    }
    expect(
      () => ProviderType.fromWire('nope'),
      throwsA(isA<ValidationException>()),
    );
  });

  test('AccessMode helpers and wire', () {
    expect(AccessMode.readOnly.isReadOnly, isTrue);
    expect(AccessMode.readWrite.isReadWrite, isTrue);
    expect(AccessMode.fromWire('readWrite'), AccessMode.readWrite);
  });

  test('MountType / SyncStatus / ConflictKind wire round-trip', () {
    for (final v in MountType.values) {
      expect(MountType.fromWire(v.wireValue), v);
    }
    for (final v in SyncStatus.values) {
      expect(SyncStatus.fromWire(v.wireValue), v);
    }
    for (final v in ConflictKind.values) {
      expect(ConflictKind.fromWire(v.wireValue), v);
    }
  });
}
