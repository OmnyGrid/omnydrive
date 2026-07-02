/// OmnyDrive — a unified abstraction for files and directories that may live
/// locally, on remote devices, or in Git repositories.
///
/// This library exposes the engine-side public API: the domain model, provider
/// contracts and implementations, application services, the hub and endpoint
/// servers, and shared utilities. Consumers who only need to talk to a running
/// hub or endpoint should import `package:omnydrive/omnydrive_client.dart`
/// instead.
library;

// Shared.
export 'src/shared/version.dart';
export 'src/shared/errors/error_codes.dart';
export 'src/shared/errors/domain_exception.dart';
export 'src/shared/json/json_response.dart';
export 'src/shared/utils/clock.dart';
export 'src/shared/utils/id_generator.dart';
export 'src/shared/utils/retry_policy.dart';
export 'src/shared/utils/atomic_file.dart';
export 'src/shared/utils/file_lock.dart';
export 'src/shared/utils/content_compression.dart';
export 'src/shared/utils/omny_ignore.dart';
export 'src/shared/observability/logger.dart';
export 'src/shared/observability/progress.dart';
export 'src/shared/observability/metrics.dart';
export 'src/shared/observability/events.dart';

// Domain — enums.
export 'src/domain/enums/provider_type.dart';
export 'src/domain/enums/access_mode.dart';
export 'src/domain/enums/mount_type.dart';
export 'src/domain/enums/sync_status.dart';
export 'src/domain/enums/conflict_kind.dart';

// Domain — value objects.
export 'src/domain/value_objects/drive_id.dart';
export 'src/domain/value_objects/endpoint_id.dart';
export 'src/domain/value_objects/hub_id.dart';
export 'src/domain/value_objects/mount_id.dart';
export 'src/domain/value_objects/local_path.dart';
export 'src/domain/value_objects/origin_uri.dart';
export 'src/domain/value_objects/path_filter.dart';
export 'src/domain/value_objects/sync_ref.dart';
export 'src/domain/value_objects/content_hash.dart';
export 'src/domain/value_objects/branch_name.dart';
export 'src/domain/value_objects/auth_token.dart';
export 'src/domain/value_objects/git_credential.dart';
export 'src/domain/value_objects/capability.dart';

// Domain — entities.
export 'src/domain/entities/drive.dart';
export 'src/domain/entities/drive_capabilities.dart';
export 'src/domain/entities/mount_info.dart';
export 'src/domain/entities/sync_state.dart';
export 'src/domain/entities/sync_plan.dart';
export 'src/domain/entities/sync_result.dart';
export 'src/domain/entities/conflict.dart';
export 'src/domain/entities/file_manifest.dart';
export 'src/domain/entities/file_manifest_entry.dart';
export 'src/domain/entities/endpoint_identity.dart';
export 'src/domain/entities/endpoint_registration.dart';
export 'src/domain/entities/drive_registration.dart';
export 'src/domain/entities/git_divergence.dart';

// Domain — contracts.
export 'src/domain/contracts/content_source.dart';
export 'src/domain/contracts/drive_provider.dart';
export 'src/domain/contracts/git_credential_resolver.dart';
export 'src/domain/contracts/mounted_drive.dart';
export 'src/domain/contracts/synchronizer.dart';
export 'src/domain/contracts/drive_hub.dart';
export 'src/domain/contracts/drive_endpoint.dart';

// Domain — repositories.
export 'src/domain/repositories/drive_registry.dart';
export 'src/domain/repositories/endpoint_registry.dart';
export 'src/domain/repositories/mount_registry.dart';
export 'src/domain/repositories/sync_state_store.dart';

// Domain — pure services.
export 'src/domain/services/conflict_detector.dart';
export 'src/domain/services/manifest_differ.dart';
export 'src/domain/services/capability_negotiator.dart';
export 'src/domain/services/branch_naming_strategy.dart';

// Infrastructure — in-memory persistence.
export 'src/infrastructure/persistence/in_memory_drive_registry.dart';
export 'src/infrastructure/persistence/in_memory_endpoint_registry.dart';
export 'src/infrastructure/persistence/in_memory_mount_registry.dart';
export 'src/infrastructure/persistence/in_memory_sync_state_store.dart';

// Infrastructure — file-backed persistence.
export 'src/infrastructure/persistence/file/file_drive_registry.dart';
export 'src/infrastructure/persistence/file/file_mount_registry.dart';
export 'src/infrastructure/persistence/file/file_sync_state_store.dart';
export 'src/infrastructure/persistence/git_credential_store.dart';

// Infrastructure — directory provider.
export 'src/infrastructure/providers/directory/manifest_builder.dart';
export 'src/infrastructure/providers/directory/local_content_source.dart';
export 'src/infrastructure/providers/directory/directory_mounted_drive.dart';
export 'src/infrastructure/providers/directory/directory_synchronizer.dart';
export 'src/infrastructure/providers/directory/directory_provider.dart';

// Infrastructure — git provider.
export 'src/infrastructure/providers/git/git_cli.dart';
export 'src/infrastructure/providers/git/git_mounted_drive.dart';
export 'src/infrastructure/providers/git/git_synchronizer.dart';
export 'src/infrastructure/providers/git/git_provider.dart';

// Application — orchestration of providers, registries and the hub.
export 'src/application/provider_registry.dart';
export 'src/application/local_drive_hub.dart';
export 'src/application/local_drive_endpoint.dart';

// Infrastructure — HTTP transport (servers + clients).
export 'src/infrastructure/http/hub_server.dart';
export 'src/infrastructure/http/content_server.dart';
export 'src/infrastructure/http/http_drive_hub.dart';
export 'src/infrastructure/http/http_content_source.dart';
export 'src/infrastructure/http/networked_providers.dart';
export 'src/infrastructure/http/api_errors.dart';

// Client — high-level facade for consumers of a running hub.
export 'src/client/omny_client.dart';
