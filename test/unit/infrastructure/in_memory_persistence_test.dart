import 'package:omnydrive/omnydrive.dart';
import 'package:test/test.dart';

void main() {
  final endpoint = EndpointId('nas');
  final driveId = DriveId.scoped(endpoint: endpoint, name: 'docs');
  final now = DateTime.utc(2026, 1, 1);

  DriveRegistration registration() => DriveRegistration(
    drive: Drive(
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
    ),
    servingEndpoint: endpoint,
    serveUrl: 'http://nas:9100',
    registeredAt: now,
  );

  test('drive registry stores, finds, lists by endpoint, deletes', () async {
    final registry = InMemoryDriveRegistry();
    await registry.save(registration());

    expect((await registry.findById(driveId))!.serveUrl, 'http://nas:9100');
    expect((await registry.findAll()).length, 1);
    expect((await registry.findByEndpoint(endpoint)).length, 1);
    expect(await registry.findByEndpoint(EndpointId('other')), isEmpty);

    await registry.delete(driveId);
    expect(await registry.findById(driveId), isNull);
  });

  test('endpoint registry round-trips', () async {
    final registry = InMemoryEndpointRegistry();
    final reg = EndpointRegistration(
      identity: EndpointIdentity(
        id: endpoint,
        displayName: 'NAS',
        baseUrl: 'http://nas:9100',
        capabilities: CapabilitySet([Capability.read]),
        registeredAt: now,
      ),
      secretHash: 'hash',
    );
    await registry.save(reg);
    expect((await registry.findById(endpoint))!.secretHash, 'hash');
    expect((await registry.findAll()).length, 1);
  });

  test('mount registry finds by path and drive', () async {
    final registry = InMemoryMountRegistry();
    final mount = MountInfo(
      id: MountId('mount_1'),
      driveId: driveId,
      localPath: LocalPath('/work/docs'),
      accessMode: AccessMode.readWrite,
      mountType: MountType.mirror,
      mountedAt: now,
      syncState: SyncState(baselineRef: SyncRef.directory('a')),
    );
    await registry.save(mount);
    expect(
      (await registry.findByPath(LocalPath('/work/docs')))!.id.value,
      'mount_1',
    );
    expect((await registry.findByDrive(driveId)).length, 1);
  });

  test('sync state store load/save/delete', () async {
    final store = InMemorySyncStateStore();
    final mountId = MountId('mount_1');
    expect(await store.load(mountId), isNull);

    await store.save(mountId, SyncState(baselineRef: SyncRef.directory('a')));
    expect((await store.load(mountId))!.baselineRef, SyncRef.directory('a'));

    await store.delete(mountId);
    expect(await store.load(mountId), isNull);
  });
}
