import '../domain/entities/endpoint_identity.dart';

/// The credentials handed back to an endpoint when it first enrolls with a hub.
///
/// The raw [secret] is the only time it is ever revealed — the hub stores only
/// its hash. The endpoint must persist it to authenticate later.
class Enrollment {
  final EndpointIdentity identity;
  final String secret;

  const Enrollment({required this.identity, required this.secret});
}
