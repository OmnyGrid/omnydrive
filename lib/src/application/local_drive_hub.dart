import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../domain/contracts/drive_hub.dart';
import '../domain/entities/drive_registration.dart';
import '../domain/entities/endpoint_identity.dart';
import '../domain/entities/endpoint_registration.dart';
import '../domain/repositories/drive_registry.dart';
import '../domain/repositories/endpoint_registry.dart';
import '../domain/value_objects/auth_token.dart';
import '../domain/value_objects/drive_id.dart';
import '../domain/value_objects/endpoint_id.dart';
import '../domain/value_objects/hub_id.dart';
import '../infrastructure/persistence/in_memory_drive_registry.dart';
import '../infrastructure/persistence/in_memory_endpoint_registry.dart';
import '../shared/errors/domain_exception.dart';
import '../shared/errors/error_codes.dart';
import '../shared/utils/clock.dart';
import '../shared/utils/id_generator.dart';
import 'enrollment.dart';

export 'enrollment.dart';

/// In-process [DriveHub]: the central coordinator's logic, free of any HTTP
/// concerns. The shelf hub server is a thin adapter over this class.
///
/// It owns endpoint enrollment + token auth, the drive registry and sync
/// routing. It never touches a filesystem — it only brokers metadata.
class LocalDriveHub implements DriveHub {
  final HubId id;
  final EndpointRegistry endpoints;
  final DriveRegistry drives;

  final IdGenerator _ids;
  final Clock _clock;

  /// Issued bearer token -> the endpoint it authenticates.
  final Map<String, EndpointId> _tokens = {};

  LocalDriveHub({
    HubId? id,
    EndpointRegistry? endpoints,
    DriveRegistry? drives,
    IdGenerator? idGenerator,
    Clock? clock,
  }) : id = id ?? HubId('hub'),
       endpoints = endpoints ?? InMemoryEndpointRegistry(),
       drives = drives ?? InMemoryDriveRegistry(),
       _ids = idGenerator ?? RandomIdGenerator(),
       _clock = clock ?? SystemClock();

  // --- Endpoint enrollment & authentication ---------------------------------

  /// Enrolls a brand-new endpoint, generating (or accepting) its shared secret
  /// and returning it exactly once. Throws [ConflictException] if the endpoint
  /// id is already registered.
  ///
  /// This is the entry point real clients use; [registerEndpoint] is the
  /// interface-level idempotent upsert that does not surface the secret.
  Future<Enrollment> enroll({
    required EndpointIdentity identity,
    String? secret,
  }) async {
    if (await endpoints.findById(identity.id) != null) {
      throw const ConflictException(
        code: ErrorCodes.endpointAlreadyExists,
        message: 'Endpoint is already registered',
      );
    }
    final raw = secret ?? _ids.next('secret');
    final stamped = _stamp(identity);
    await endpoints.save(
      EndpointRegistration(identity: stamped, secretHash: _hash(raw)),
    );
    return Enrollment(identity: stamped, secret: raw);
  }

  @override
  Future<EndpointIdentity> registerEndpoint(EndpointIdentity identity) async {
    final existing = await endpoints.findById(identity.id);
    final secretHash = existing?.secretHash ?? _hash(_ids.next('secret'));
    final stamped = _stamp(identity);
    await endpoints.save(
      EndpointRegistration(identity: stamped, secretHash: secretHash),
    );
    return stamped;
  }

  @override
  Future<AuthToken> authenticate({
    required EndpointId endpointId,
    required String secret,
  }) async {
    final reg = await endpoints.findById(endpointId);
    if (reg == null || reg.secretHash != _hash(secret)) {
      throw const UnauthorizedException('Invalid endpoint id or secret');
    }
    final token = _ids.next('token');
    _tokens[token] = endpointId;
    return AuthToken(token);
  }

  /// Resolves the endpoint a bearer [token] authenticates, or throws
  /// [UnauthorizedException]. Used by the hub server's auth middleware.
  EndpointId authorize(AuthToken token) {
    final endpoint = _tokens[token.value];
    if (endpoint == null) throw const UnauthorizedException();
    return endpoint;
  }

  // --- Drive registry & routing ---------------------------------------------

  @override
  Future<DriveRegistration> registerDrive(
    DriveRegistration registration,
  ) async {
    if (await endpoints.findById(registration.servingEndpoint) == null) {
      throw NotFoundException(
        code: ErrorCodes.endpointNotFound,
        message:
            'Serving endpoint "${registration.servingEndpoint}" is not registered',
      );
    }
    final stamped = DriveRegistration(
      drive: registration.drive,
      servingEndpoint: registration.servingEndpoint,
      serveUrl: registration.serveUrl,
      registeredAt: _clock.now(),
    );
    await drives.save(stamped);
    return stamped;
  }

  @override
  Future<List<DriveRegistration>> listDrives() => drives.findAll();

  @override
  Future<DriveRegistration> getDrive(DriveId id) async {
    final reg = await drives.findById(id);
    if (reg == null) {
      throw NotFoundException(
        code: ErrorCodes.driveNotFound,
        message: 'Drive "$id" is not registered',
      );
    }
    return reg;
  }

  @override
  Future<DriveRoute> routeSync(
    DriveId id, {
    required EndpointId requester,
  }) async {
    final reg = await getDrive(id);
    return DriveRoute(
      driveId: reg.id,
      servingEndpoint: reg.servingEndpoint,
      serveUrl: reg.serveUrl,
    );
  }

  // --- Helpers --------------------------------------------------------------

  String _hash(String raw) => sha256.convert(utf8.encode(raw)).toString();

  EndpointIdentity _stamp(EndpointIdentity identity) => EndpointIdentity(
    id: identity.id,
    displayName: identity.displayName,
    baseUrl: identity.baseUrl,
    capabilities: identity.capabilities,
    publicKey: identity.publicKey,
    registeredAt: _clock.now(),
  );
}
