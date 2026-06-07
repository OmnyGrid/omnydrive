import 'package:omnydrive/omnydrive.dart';
import 'package:test/test.dart';

void main() {
  final endpoint = EndpointId('nas');
  final driveId = DriveId.scoped(endpoint: endpoint, name: 'docs');
  final now = DateTime.utc(2026, 1, 1);

  Drive sampleDrive() => Drive(
    id: driveId,
    name: 'docs',
    provider: ProviderType.directory,
    originEndpoint: endpoint,
    originUri: OriginUri('/data/docs'),
    accessMode: AccessMode.readWrite,
    capabilities: DriveCapabilities.forProvider(
      ProviderType.directory,
      AccessMode.readWrite,
    ),
    createdAt: now,
  );

  test('Drive round-trips through JSON', () {
    final drive = sampleDrive();
    final restored = Drive.fromJson(drive.toJson());
    expect(restored.id, drive.id);
    expect(restored.provider, ProviderType.directory);
    expect(restored.accessMode, AccessMode.readWrite);
    expect(restored.capabilities, drive.capabilities);
  });

  test('DriveCapabilities.forProvider strips writes in read-only', () {
    final ro = DriveCapabilities.forProvider(
      ProviderType.git,
      AccessMode.readOnly,
    );
    expect(ro.canRead, isTrue);
    expect(ro.canPush, isFalse);
    expect(ro.canWrite, isFalse);

    final rw = DriveCapabilities.forProvider(
      ProviderType.git,
      AccessMode.readWrite,
    );
    expect(rw.canPush, isTrue);
    expect(rw.canBranch, isTrue);
  });

  test('MountInfo + SyncState round-trip', () {
    final mount = MountInfo(
      id: MountId('mount_1'),
      driveId: driveId,
      localPath: LocalPath('/work/docs'),
      accessMode: AccessMode.readWrite,
      mountType: MountType.mirror,
      mountedAt: now,
      syncState: SyncState(
        baselineRef: SyncRef.directory('abc'),
        status: SyncStatus.clean,
      ),
    );
    final restored = MountInfo.fromJson(mount.toJson());
    expect(restored.id, mount.id);
    expect(restored.mountType, MountType.mirror);
    expect(restored.syncState.baselineRef, SyncRef.directory('abc'));
  });

  test('FileManifest hash is order-independent and content-addressed', () {
    final e1 = FileManifestEntry(
      path: 'a.txt',
      size: 3,
      hash: ContentHash(hex: 'aa'),
    );
    final e2 = FileManifestEntry(
      path: 'b.txt',
      size: 5,
      hash: ContentHash(hex: 'bb'),
    );
    final m1 = FileManifest({'a.txt': e1, 'b.txt': e2});
    final m2 = FileManifest({'b.txt': e2, 'a.txt': e1});
    expect(m1.hash(), equals(m2.hash()));

    // Changing content changes the hash.
    final e2b = FileManifestEntry(
      path: 'b.txt',
      size: 5,
      hash: ContentHash(hex: 'cc'),
    );
    final m3 = FileManifest({'a.txt': e1, 'b.txt': e2b});
    expect(m3.hash(), isNot(equals(m1.hash())));
  });

  test('FileManifest JSON round-trips', () {
    final m = FileManifest({
      'a.txt': FileManifestEntry(
        path: 'a.txt',
        size: 1,
        hash: ContentHash(hex: 'ab'),
      ),
    });
    final restored = FileManifest.fromJson(m.toJson());
    expect(restored.hash(), m.hash());
  });

  test('Conflict round-trips through JSON', () {
    final c = Conflict(
      kind: ConflictKind.refMoved,
      driveId: driveId,
      expectedRef: SyncRef.directory('old'),
      actualRef: SyncRef.directory('new'),
      message: 'moved',
    );
    final restored = Conflict.fromJson(c.toJson());
    expect(restored.kind, ConflictKind.refMoved);
    expect(restored.expectedRef, SyncRef.directory('old'));
    expect(restored.actualRef, SyncRef.directory('new'));
  });

  test('DriveRegistration + EndpointIdentity round-trip', () {
    final identity = EndpointIdentity(
      id: endpoint,
      displayName: 'NAS',
      baseUrl: 'http://nas:9100',
      capabilities: CapabilitySet([Capability.read, Capability.clone]),
      registeredAt: now,
    );
    final restoredId = EndpointIdentity.fromJson(identity.toJson());
    expect(restoredId.id, endpoint);
    expect(restoredId.capabilities, identity.capabilities);

    final reg = DriveRegistration(
      drive: sampleDrive(),
      servingEndpoint: endpoint,
      serveUrl: 'http://nas:9100',
      registeredAt: now,
    );
    final restoredReg = DriveRegistration.fromJson(reg.toJson());
    expect(restoredReg.id, driveId);
    expect(restoredReg.serveUrl, 'http://nas:9100');
  });
}
