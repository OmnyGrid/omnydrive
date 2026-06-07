/// Entry point for the `omnydrive` command-line tool, exposed as a library so
/// it can be driven from tests as well as `bin/omnydrive.dart`.
library;

export 'src/cli/cli.dart' show runOmnydrive, CliException;
