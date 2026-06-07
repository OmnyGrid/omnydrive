import '../enums/access_mode.dart';
import '../value_objects/capability.dart';

/// Pure capability negotiation. Given what a drive supports and the access mode
/// a caller requested, computes the effective capabilities, dropping any
/// write-flavored capability in read-only mode. No I/O.
class CapabilityNegotiator {
  static const _writeCapabilities = {
    Capability.write,
    Capability.push,
    Capability.branch,
  };

  const CapabilityNegotiator();

  /// Returns the capabilities effectively granted for [requested] access given
  /// the drive's [supported] set.
  CapabilitySet negotiate({
    required CapabilitySet supported,
    required AccessMode requested,
  }) {
    if (requested.isReadWrite) return supported;
    // Read-only: strip every write-flavored capability.
    return CapabilitySet(
      supported.values.where((c) => !_writeCapabilities.contains(c)),
    );
  }

  /// Whether [capability] is permitted under [accessMode] for a drive that
  /// [supported] it.
  bool permits({
    required CapabilitySet supported,
    required AccessMode accessMode,
    required Capability capability,
  }) => negotiate(supported: supported, requested: accessMode).has(capability);
}
