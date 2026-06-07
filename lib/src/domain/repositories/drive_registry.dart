import '../entities/drive_registration.dart';
import '../value_objects/drive_id.dart';
import '../value_objects/endpoint_id.dart';

/// Persists the hub's registry of published drives.
abstract interface class DriveRegistry {
  Future<void> save(DriveRegistration registration);
  Future<DriveRegistration?> findById(DriveId id);
  Future<List<DriveRegistration>> findAll();
  Future<List<DriveRegistration>> findByEndpoint(EndpointId endpoint);
  Future<void> delete(DriveId id);
}
