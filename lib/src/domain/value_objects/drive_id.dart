import '../../shared/errors/domain_exception.dart';
import 'endpoint_id.dart';

/// Identifies a published drive, scoped to its origin endpoint so ids are
/// unique across the network and human-readable: `<endpointId>/<name-slug>`.
class DriveId {
  static final RegExp _pattern = RegExp(
    r'^[a-z0-9][a-z0-9_-]{0,63}/[a-z0-9][a-z0-9_.-]{0,99}$',
  );

  final String value;

  DriveId(String input) : value = input.trim() {
    if (value.isEmpty) {
      throw const ValidationException('Drive id is required');
    }
    if (!_pattern.hasMatch(value)) {
      throw ValidationException(
        'Invalid drive id "$value": expected "<endpointId>/<name>"',
      );
    }
  }

  /// Builds a drive id from its owning [endpoint] and a drive [name],
  /// normalizing the name into a slug.
  factory DriveId.scoped({required EndpointId endpoint, required String name}) {
    final slug = _slugify(name);
    if (slug.isEmpty) {
      throw ValidationException('Drive name "$name" produced an empty slug');
    }
    return DriveId('${endpoint.value}/$slug');
  }

  /// The endpoint portion of the id.
  EndpointId get endpoint => EndpointId(value.split('/').first);

  /// The drive name portion of the id.
  String get name => value.substring(value.indexOf('/') + 1);

  static String _slugify(String input) {
    final lower = input.trim().toLowerCase();
    final replaced = lower.replaceAll(RegExp(r'[^a-z0-9_.-]+'), '-');
    return replaced.replaceAll(RegExp(r'^-+|-+$'), '');
  }

  @override
  bool operator ==(Object other) => other is DriveId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
