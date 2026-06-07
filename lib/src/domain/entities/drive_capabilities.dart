import '../enums/access_mode.dart';
import '../enums/provider_type.dart';
import '../value_objects/capability.dart';

/// What operations a drive supports, derived from its provider and access mode.
class DriveCapabilities {
  final bool canRead;
  final bool canWrite;
  final bool canClone;
  final bool canMirror;
  final bool canPush;
  final bool canBranch;

  const DriveCapabilities({
    this.canRead = false,
    this.canWrite = false,
    this.canClone = false,
    this.canMirror = false,
    this.canPush = false,
    this.canBranch = false,
  });

  /// Computes the default capability profile for a [provider] under an
  /// [accessMode]. Write-flavored capabilities are off in read-only mode.
  factory DriveCapabilities.forProvider(
    ProviderType provider,
    AccessMode accessMode,
  ) {
    final writable = accessMode.isReadWrite;
    switch (provider) {
      case ProviderType.directory:
        return DriveCapabilities(
          canRead: true,
          canClone: true,
          canMirror: true,
          canWrite: writable,
        );
      case ProviderType.git:
        return DriveCapabilities(
          canRead: true,
          canClone: true,
          canMirror: true,
          canWrite: writable,
          canPush: writable,
          canBranch: writable,
        );
    }
  }

  /// Converts the booleans into a [CapabilitySet].
  CapabilitySet toSet() => CapabilitySet([
    if (canRead) Capability.read,
    if (canWrite) Capability.write,
    if (canClone) Capability.clone,
    if (canMirror) Capability.mirror,
    if (canPush) Capability.push,
    if (canBranch) Capability.branch,
  ]);

  Map<String, dynamic> toJson() => {
    'canRead': canRead,
    'canWrite': canWrite,
    'canClone': canClone,
    'canMirror': canMirror,
    'canPush': canPush,
    'canBranch': canBranch,
  };

  factory DriveCapabilities.fromJson(Map<String, dynamic> json) =>
      DriveCapabilities(
        canRead: json['canRead'] as bool? ?? false,
        canWrite: json['canWrite'] as bool? ?? false,
        canClone: json['canClone'] as bool? ?? false,
        canMirror: json['canMirror'] as bool? ?? false,
        canPush: json['canPush'] as bool? ?? false,
        canBranch: json['canBranch'] as bool? ?? false,
      );

  @override
  bool operator ==(Object other) =>
      other is DriveCapabilities &&
      other.canRead == canRead &&
      other.canWrite == canWrite &&
      other.canClone == canClone &&
      other.canMirror == canMirror &&
      other.canPush == canPush &&
      other.canBranch == canBranch;

  @override
  int get hashCode =>
      Object.hash(canRead, canWrite, canClone, canMirror, canPush, canBranch);
}
