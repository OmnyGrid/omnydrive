import '../../../domain/entities/drive_registration.dart';
import '../../../domain/repositories/drive_registry.dart';
import '../../../domain/value_objects/drive_id.dart';
import '../../../domain/value_objects/endpoint_id.dart';
import '../../../shared/utils/atomic_file.dart';

/// A [DriveRegistry] persisted as a single JSON document.
///
/// Each operation reads the file fresh and writes it back atomically, so a
/// long-running content server picks up drives published by a separate CLI
/// process. Intended for single-host, low-contention use.
class FileDriveRegistry implements DriveRegistry {
  final String path;

  FileDriveRegistry(this.path);

  Future<List<DriveRegistration>> _load() async {
    final json = await AtomicFile.readJson(path);
    if (json == null) return [];
    final list = (json['drives'] as List?) ?? const [];
    return list
        .cast<Map<String, dynamic>>()
        .map(DriveRegistration.fromJson)
        .toList();
  }

  Future<void> _store(List<DriveRegistration> drives) =>
      AtomicFile.writeJson(path, {
        'drives': [for (final d in drives) d.toJson()],
      });

  @override
  Future<void> save(DriveRegistration registration) async {
    final drives = await _load()
      ..removeWhere((d) => d.id == registration.id)
      ..add(registration);
    await _store(drives);
  }

  @override
  Future<DriveRegistration?> findById(DriveId id) async {
    for (final d in await _load()) {
      if (d.id == id) return d;
    }
    return null;
  }

  @override
  Future<List<DriveRegistration>> findAll() async {
    final drives = await _load()
      ..sort((a, b) => a.id.value.compareTo(b.id.value));
    return List.unmodifiable(drives);
  }

  @override
  Future<List<DriveRegistration>> findByEndpoint(EndpointId endpoint) async =>
      List.unmodifiable(
        (await _load()).where((d) => d.servingEndpoint == endpoint),
      );

  @override
  Future<void> delete(DriveId id) async {
    final drives = await _load()
      ..removeWhere((d) => d.id == id);
    await _store(drives);
  }
}
