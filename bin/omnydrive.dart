import 'dart:io';

import 'package:omnydrive/omnydrive_cli.dart';

Future<void> main(List<String> args) async {
  exitCode = await runOmnydrive(args);
}
