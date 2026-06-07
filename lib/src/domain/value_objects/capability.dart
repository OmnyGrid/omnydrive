import '../../shared/errors/domain_exception.dart';

/// A discrete operation a drive may support.
enum Capability {
  read,
  write,
  clone,
  mirror,
  push,
  branch;

  String get wireValue => name;

  static Capability fromWire(String value) => values.firstWhere(
    (e) => e.wireValue == value,
    orElse: () => throw ValidationException('Unknown capability: $value'),
  );
}

/// An immutable set of [Capability] values with convenient wire conversion.
class CapabilitySet {
  final Set<Capability> _values;

  CapabilitySet(Iterable<Capability> values)
    : _values = Set.unmodifiable(values);

  /// An empty capability set.
  static final empty = CapabilitySet(const []);

  bool has(Capability capability) => _values.contains(capability);

  Set<Capability> get values => _values;

  /// Returns the intersection of this set with [other].
  CapabilitySet intersect(CapabilitySet other) =>
      CapabilitySet(_values.where(other.has));

  List<String> toJson() => _values.map((c) => c.wireValue).toList()..sort();

  factory CapabilitySet.fromJson(List<dynamic> json) =>
      CapabilitySet(json.map((e) => Capability.fromWire(e as String)));

  @override
  bool operator ==(Object other) =>
      other is CapabilitySet &&
      other._values.length == _values.length &&
      other._values.containsAll(_values);

  @override
  int get hashCode => Object.hashAllUnordered(_values.map((c) => c.index));

  @override
  String toString() => 'CapabilitySet(${toJson().join(', ')})';
}
