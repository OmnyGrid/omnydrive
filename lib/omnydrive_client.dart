/// OmnyDrive client SDK — everything needed to talk to a running hub and the
/// endpoint content servers it routes to, without depending on the engine
/// (providers, servers, persistence).
///
/// Start from [OmnyClient]; drop down to [HttpDriveHub] / [HttpContentSource]
/// for finer control. Errors surface as the same [DomainException] subtypes the
/// engine raises, decoded from the wire by [throwApiError].
library;

// High-level facade.
export 'src/client/omny_client.dart';

// HTTP clients.
export 'src/infrastructure/http/http_drive_hub.dart';
export 'src/infrastructure/http/http_content_source.dart';
export 'src/infrastructure/http/api_errors.dart';

// Contracts a consumer interacts with.
export 'src/domain/contracts/content_source.dart';
export 'src/domain/contracts/drive_hub.dart' show DriveHub, DriveRoute;

// Credentials.
export 'src/application/enrollment.dart';

// Enums.
export 'src/domain/enums/provider_type.dart';
export 'src/domain/enums/access_mode.dart';
export 'src/domain/enums/mount_type.dart';
export 'src/domain/enums/sync_status.dart';
export 'src/domain/enums/conflict_kind.dart';

// Value objects.
export 'src/domain/value_objects/drive_id.dart';
export 'src/domain/value_objects/endpoint_id.dart';
export 'src/domain/value_objects/hub_id.dart';
export 'src/domain/value_objects/mount_id.dart';
export 'src/domain/value_objects/origin_uri.dart';
export 'src/domain/value_objects/path_filter.dart';
export 'src/domain/value_objects/sync_ref.dart';
export 'src/domain/value_objects/content_hash.dart';
export 'src/domain/value_objects/auth_token.dart';
export 'src/domain/value_objects/capability.dart';

// Entities exchanged with the hub / content servers.
export 'src/domain/entities/drive.dart';
export 'src/domain/entities/drive_capabilities.dart';
export 'src/domain/entities/drive_registration.dart';
export 'src/domain/entities/endpoint_identity.dart';
export 'src/domain/entities/mount_info.dart';
export 'src/domain/entities/sync_state.dart';
export 'src/domain/entities/sync_result.dart';
export 'src/domain/entities/conflict.dart';
export 'src/domain/entities/file_manifest.dart';
export 'src/domain/entities/file_manifest_entry.dart';

// Errors & version.
export 'src/shared/errors/error_codes.dart';
export 'src/shared/errors/domain_exception.dart';
export 'src/shared/version.dart';
