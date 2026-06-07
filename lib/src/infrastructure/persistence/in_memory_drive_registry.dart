import '../../domain/entities/drive_registration.dart';
import '../../domain/repositories/drive_registry.dart';
import '../../domain/value_objects/drive_id.dart';
import '../../domain/value_objects/endpoint_id.dart';

/// In-memory [DriveRegistry]. The default for tests and single-process hubs.
class InMemoryDriveRegistry implements DriveRegistry {
  final Map<String, DriveRegistration> _drives = {};

  @override
  Future<void> save(DriveRegistration registration) async {
    _drives[registration.id.value] = registration;
  }

  @override
  Future<DriveRegistration?> findById(DriveId id) async => _drives[id.value];

  @override
  Future<List<DriveRegistration>> findAll() async => List.unmodifiable(
    _drives.values.toList()..sort((a, b) => a.id.value.compareTo(b.id.value)),
  );

  @override
  Future<List<DriveRegistration>> findByEndpoint(EndpointId endpoint) async =>
      List.unmodifiable(
        _drives.values.where((d) => d.servingEndpoint == endpoint),
      );

  @override
  Future<void> delete(DriveId id) async {
    _drives.remove(id.value);
  }
}
