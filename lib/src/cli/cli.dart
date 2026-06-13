import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../application/local_drive_endpoint.dart';
import '../application/local_drive_hub.dart';
import '../domain/entities/endpoint_identity.dart';
import '../domain/value_objects/auth_token.dart';
import '../domain/value_objects/capability.dart';
import '../domain/value_objects/endpoint_id.dart';
import '../domain/value_objects/path_filter.dart';
import '../infrastructure/http/content_server.dart';
import '../infrastructure/http/http_drive_hub.dart';
import '../infrastructure/http/hub_server.dart';
import '../infrastructure/http/networked_providers.dart';
import '../infrastructure/persistence/file/file_drive_registry.dart';
import '../infrastructure/persistence/file/file_mount_registry.dart';
import '../infrastructure/persistence/file/file_sync_state_store.dart';
import '../shared/errors/domain_exception.dart';
import '../shared/version.dart';
import 'endpoint_config.dart';
import 'sync_progress.dart';

/// A user-facing CLI error that maps to a clean message and exit code 1,
/// without a stack trace.
class CliException implements Exception {
  final String message;
  const CliException(this.message);
  @override
  String toString() => message;
}

/// Parses and runs the `omnydrive` command line, returning a process exit code.
Future<int> runOmnydrive(List<String> args) async {
  final runner =
      CommandRunner<int>(
          'omnydrive',
          'Distributed file & git drive synchronization (v$omnyDriveVersion).',
        )
        ..argParser.addOption(
          'state',
          help: 'Directory holding this endpoint\'s local state.',
          defaultsTo: _defaultStateDir(),
        )
        ..addCommand(ServeHubCommand())
        ..addCommand(ServeContentCommand())
        ..addCommand(LoginCommand())
        ..addCommand(PublishCommand())
        ..addCommand(CloneCommand())
        ..addCommand(SyncCommand())
        ..addCommand(MountsCommand())
        ..addCommand(DrivesCommand());

  try {
    return await runner.run(args) ?? 0;
  } on UsageException catch (e) {
    stderr.writeln(e);
    return 64;
  } on DomainException catch (e) {
    stderr.writeln('Error [${e.code}]: ${e.message}');
    return _exitCodeFor(e);
  } on CliException catch (e) {
    stderr.writeln('Error: ${e.message}');
    return 1;
  }
}

String _defaultStateDir() {
  final home =
      Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      Directory.current.path;
  return p.join(home, '.omnydrive');
}

int _exitCodeFor(DomainException e) => switch (e) {
  ValidationException() || InvalidJsonException() => 2,
  NotFoundException() => 3,
  UnauthorizedException() => 4,
  AccessDeniedException() => 5,
  ConflictException() || ConflictDetectedException() => 6,
  LockHeldException() => 7,
  _ => 1,
};

/// Shared base giving every command access to the global `--state` option and a
/// configured endpoint.
abstract class _BaseCommand extends Command<int> {
  String get stateDir => globalResults!['state'] as String;

  Future<LocalDriveEndpoint> loadEndpoint() async {
    final config = await EndpointConfig.load(stateDir);
    if (config == null) {
      throw const CliException('Not logged in — run `omnydrive login` first.');
    }
    final hub = HttpDriveHub(
      config.hubUrl,
      token: config.token == null ? null : AuthToken(config.token!),
    );
    return LocalDriveEndpoint(
      identity: config.identity,
      hub: hub,
      providers: networkedProviderRegistry(endpoint: config.identity.id),
      published: FileDriveRegistry(EndpointConfig.drivesPath(stateDir)),
      mounts: FileMountRegistry(EndpointConfig.mountsPath(stateDir)),
      syncStates: FileSyncStateStore(EndpointConfig.syncPath(stateDir)),
    );
  }
}

/// Blocks until the process receives SIGINT, then closes [server].
Future<int> _serveUntilInterrupted(HttpServer server, String label) async {
  stdout.writeln(
    '$label listening on http://${server.address.host}:'
    '${server.port}  (Ctrl-C to stop)',
  );
  final done = Completer<void>();
  late final StreamSubscription sub;
  sub = ProcessSignal.sigint.watch().listen((_) async {
    await server.close(force: true);
    await sub.cancel();
    if (!done.isCompleted) done.complete();
  });
  await done.future;
  return 0;
}

class ServeHubCommand extends _BaseCommand {
  ServeHubCommand() {
    argParser
      ..addOption('host', defaultsTo: 'localhost')
      ..addOption('port', defaultsTo: '7070');
  }

  @override
  String get name => 'serve';
  @override
  String get description => 'Run a coordinating hub server.';

  @override
  Future<int> run() async {
    final hub = LocalDriveHub();
    final server = await HubServer(hub).serve(
      address: argResults!['host'] as String,
      port: int.parse(argResults!['port'] as String),
    );
    return _serveUntilInterrupted(server, 'omnydrive hub');
  }
}

class ServeContentCommand extends _BaseCommand {
  ServeContentCommand() {
    argParser
      ..addOption('host', defaultsTo: 'localhost')
      ..addOption('port', defaultsTo: '8080');
  }

  @override
  String get name => 'serve-content';
  @override
  String get description =>
      'Serve this endpoint\'s published directory drives to peers.';

  @override
  Future<int> run() async {
    final published = FileDriveRegistry(EndpointConfig.drivesPath(stateDir));
    final server = await ContentServer(published).serve(
      address: argResults!['host'] as String,
      port: int.parse(argResults!['port'] as String),
    );
    return _serveUntilInterrupted(server, 'omnydrive content');
  }
}

class LoginCommand extends _BaseCommand {
  LoginCommand() {
    argParser
      ..addOption('hub', help: 'Hub base URL, e.g. http://hub.local:7070')
      ..addOption('id', help: 'This endpoint\'s id (slug).')
      ..addOption('name', help: 'Human-readable display name.')
      ..addOption(
        'serve-url',
        help: 'Base URL peers use to reach this endpoint\'s content server.',
      )
      ..addOption('secret', help: 'Pre-shared secret (otherwise generated).')
      ..addFlag(
        'force',
        negatable: false,
        help: 'Re-enroll even if already configured.',
      );
  }

  @override
  String get name => 'login';
  @override
  String get description =>
      'Enroll this endpoint with a hub and obtain a token.';

  @override
  Future<int> run() async {
    final existing = await EndpointConfig.load(stateDir);
    final force = argResults!['force'] as bool;

    if (existing != null && !force) {
      // Refresh the bearer token using the stored secret.
      final hub = HttpDriveHub(existing.hubUrl);
      final token = await hub.login(
        endpointId: existing.identity.id,
        secret: existing.secret,
      );
      await existing.withToken(token.value).save(stateDir);
      stdout.writeln('Re-authenticated as ${existing.identity.id}.');
      return 0;
    }

    final hubUrl = _required('hub');
    final id = _required('id');
    final serveUrl = _required('serve-url');
    final name = (argResults!['name'] as String?) ?? id;

    final hub = HttpDriveHub(hubUrl);
    final identity = EndpointIdentity(
      id: EndpointId(id),
      displayName: name,
      baseUrl: serveUrl,
      capabilities: CapabilitySet(Capability.values),
      registeredAt: DateTime.now().toUtc(),
    );
    final enrollment = await hub.enroll(
      identity: identity,
      secret: argResults!['secret'] as String?,
    );
    final token = await hub.login(
      endpointId: identity.id,
      secret: enrollment.secret,
    );
    await EndpointConfig(
      hubUrl: hubUrl,
      identity: enrollment.identity,
      secret: enrollment.secret,
      token: token.value,
    ).save(stateDir);
    stdout.writeln('Enrolled as ${identity.id} with hub $hubUrl.');
    return 0;
  }

  String _required(String option) {
    final value = argResults![option] as String?;
    if (value == null || value.isEmpty) {
      throw CliException('Missing required option --$option for a new login.');
    }
    return value;
  }
}

class PublishCommand extends _BaseCommand {
  PublishCommand() {
    argParser
      ..addOption('name', help: 'Drive name (defaults to the directory name).')
      ..addFlag('git', negatable: false, help: 'Publish a git repository URL.')
      ..addFlag(
        'read-only',
        negatable: false,
        help: 'Publish without allowing pushes.',
      )
      ..addMultiOption(
        'include',
        help:
            'Only publish sub-paths matching this glob (repeatable). '
            'Acts as a whitelist; e.g. --include "src/**".',
      )
      ..addMultiOption(
        'exclude',
        help:
            'Exclude sub-paths matching this glob (repeatable). '
            'Wins over --include; e.g. --exclude "**/*.tmp".',
      );
  }

  @override
  String get name => 'publish';
  @override
  String get description => 'Publish a directory or git repo as a drive.';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      throw const CliException('Usage: omnydrive publish <path|url> [--git]');
    }
    final endpoint = await loadEndpoint();
    final name = argResults!['name'] as String?;
    final readOnly = argResults!['read-only'] as bool;
    final isGit = argResults!['git'] as bool;
    final include = argResults!['include'] as List<String>;
    final exclude = argResults!['exclude'] as List<String>;

    if (isGit && (include.isNotEmpty || exclude.isNotEmpty)) {
      throw const CliException(
        '--include/--exclude only apply to directory drives, not --git.',
      );
    }
    final filter = (include.isEmpty && exclude.isEmpty)
        ? null
        : PathFilter(include: include, exclude: exclude);

    final drive = isGit
        ? await endpoint.publishGit(
            url: rest.first,
            name: name,
            readOnly: readOnly,
          )
        : await endpoint.publishDirectory(
            path: p.absolute(rest.first),
            name: name,
            readOnly: readOnly,
            filter: filter,
          );

    stdout.writeln('Published ${drive.id} (${drive.provider.wireValue}).');
    return 0;
  }
}

class CloneCommand extends _BaseCommand {
  CloneCommand() {
    argParser.addFlag(
      'read-only',
      negatable: false,
      help: 'Clone as a read-only mirror.',
    );
  }

  @override
  String get name => 'clone';
  @override
  String get description => 'Clone a drive from the network into a directory.';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length < 2) {
      throw const CliException('Usage: omnydrive clone <driveId> <dest>');
    }
    final endpoint = await loadEndpoint();
    final mount = await endpoint.cloneDrive(
      driveId: rest[0],
      dest: p.absolute(rest[1]),
      readOnly: argResults!['read-only'] as bool,
    );
    stdout.writeln(
      'Cloned ${mount.driveId} -> ${mount.localPath} '
      '(mount ${mount.id}).',
    );
    return 0;
  }
}

class SyncCommand extends _BaseCommand {
  SyncCommand() {
    argParser.addFlag(
      'verbose',
      abbr: 'v',
      negatable: false,
      help: 'List every transferred/copied/removed path in the final report.',
    );
  }

  @override
  String get name => 'sync';
  @override
  String get description => 'Synchronize a mount with its origin.';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      throw const CliException('Usage: omnydrive sync <mountId>');
    }
    final endpoint = await loadEndpoint();
    final renderer = SyncProgressRenderer(
      verbose: argResults!['verbose'] as bool,
    );
    final result = await endpoint.syncMount(
      rest.first,
      progress: renderer.reporter,
    );
    renderer.printReport(result);
    return 0;
  }
}

class MountsCommand extends _BaseCommand {
  @override
  String get name => 'mounts';
  @override
  String get description => 'List local mounts.';

  @override
  Future<int> run() async {
    final mounts = await FileMountRegistry(
      EndpointConfig.mountsPath(stateDir),
    ).findAll();
    if (mounts.isEmpty) {
      stdout.writeln('No mounts.');
      return 0;
    }
    for (final m in mounts) {
      stdout.writeln(
        '${m.id}  ${m.driveId}  ${m.accessMode.wireValue}  '
        '${m.syncState.status.wireValue}  ${m.localPath}',
      );
    }
    return 0;
  }
}

class DrivesCommand extends _BaseCommand {
  @override
  String get name => 'drives';
  @override
  String get description => 'List drives discoverable on the hub.';

  @override
  Future<int> run() async {
    final endpoint = await loadEndpoint();
    final drives = await endpoint.hub.listDrives();
    if (drives.isEmpty) {
      stdout.writeln('No drives registered.');
      return 0;
    }
    for (final d in drives) {
      stdout.writeln(
        '${d.id}  ${d.drive.provider.wireValue}  '
        '${d.drive.accessMode.wireValue}  ${d.serveUrl}',
      );
    }
    return 0;
  }
}
