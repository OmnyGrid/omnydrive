import '../../domain/entities/endpoint_registration.dart';
import '../../domain/repositories/endpoint_registry.dart';
import '../../domain/value_objects/endpoint_id.dart';

/// In-memory [EndpointRegistry]. The default for tests and single-process hubs.
class InMemoryEndpointRegistry implements EndpointRegistry {
  final Map<String, EndpointRegistration> _endpoints = {};

  @override
  Future<void> save(EndpointRegistration registration) async {
    _endpoints[registration.identity.id.value] = registration;
  }

  @override
  Future<EndpointRegistration?> findById(EndpointId id) async =>
      _endpoints[id.value];

  @override
  Future<List<EndpointRegistration>> findAll() async => List.unmodifiable(
    _endpoints.values.toList()
      ..sort((a, b) => a.identity.id.value.compareTo(b.identity.id.value)),
  );

  @override
  Future<void> delete(EndpointId id) async {
    _endpoints.remove(id.value);
  }
}
