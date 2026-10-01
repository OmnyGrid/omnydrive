import 'dart:io';

import 'package:omnydrive/omnydrive.dart';
import 'package:test/test.dart';

void main() {
  // The constant is what `GET /version` and the CLI report; it drifted to a
  // stale value once because only pubspec.yaml was bumped.
  test('omnyDriveVersion matches pubspec.yaml version', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'''^version:\s*['"]?([^\s'"]+)['"]?''',
      multiLine: true,
    ).firstMatch(pubspec);
    expect(match, isNotNull, reason: 'no version: line in pubspec.yaml');
    expect(omnyDriveVersion, match!.group(1));
  });
}
