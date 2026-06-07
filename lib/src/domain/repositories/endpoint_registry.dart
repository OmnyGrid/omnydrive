import '../entities/endpoint_registration.dart';
import '../value_objects/endpoint_id.dart';

/// Persists the hub's registry of known endpoints.
abstract interface class EndpointRegistry {
  Future<void> save(EndpointRegistration registration);
  Future<EndpointRegistration?> findById(EndpointId id);
  Future<List<EndpointRegistration>> findAll();
  Future<void> delete(EndpointId id);
}
