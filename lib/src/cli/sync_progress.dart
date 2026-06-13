import 'dart:io';

import '../domain/entities/sync_result.dart';
import '../shared/observability/progress.dart';

/// Renders sync transfer progress for the CLI and prints a final report.
///
/// On a terminal it draws a live, self-refreshing block: one bar per in-flight
/// upload plus a summary line, redrawn (throttled) as byte progress arrives.
/// When stdout is not a terminal (piped/redirected) it falls back to one plain
/// line per completed file so the output stays grep-friendly.
class SyncProgressRenderer {
  /// Whether to list every affected path in the final report.
  final bool verbose;

  final IOSink _out;
  final bool _live;

  final Map<String, _Item> _active = {};
  int _completed = 0;
  int _total = 0;
  int _bytes = 0;

  /// Lines currently occupied by the live block, so the next redraw can erase it.
  int _renderedLines = 0;
  DateTime _lastRender = DateTime.fromMillisecondsSinceEpoch(0);

  SyncProgressRenderer({this.verbose = false, IOSink? out, bool? live})
    : _out = out ?? stdout,
      _live = live ?? stdout.hasTerminal;

  /// The reporter to hand to `syncMount`.
  ProgressReporter get reporter => ProgressReporter(_onEvent);

  void _onEvent(ProgressEvent e) {
    if (e.total != null) _total = e.total!;
    if (e.completed != null) _completed = e.completed!;
    if (e.bytes != null) _bytes = e.bytes!;

    final path = e.path;
    final state = e.itemState;
    if (path != null && state != null) {
      if (state == ProgressItemState.completed) {
        _active.remove(path);
        if (!_live) _printPlainCompletion(path, e);
      } else {
        _active[path] = _Item(
          kind: e.itemKind ?? ProgressItemKind.transferred,
          bytes: e.itemBytes,
          totalBytes: e.itemTotalBytes,
          size: e.itemSize,
        );
      }
    }

    if (e.phase == ProgressPhase.done) _active.clear();

    if (_live) {
      _maybeRender(
        force:
            e.phase == ProgressPhase.done ||
            state == ProgressItemState.started ||
            state == ProgressItemState.completed,
      );
    }
  }

  /// Prints the final summary report from a completed [result].
  void printReport(SyncResult result) {
    if (_live) _clearLiveBlock();
    final m = result.metrics;
    final branch = result.publishedBranch == null
        ? ''
        : ' (branch ${result.publishedBranch})';
    final secs = (m.duration.inMilliseconds / 1000).toStringAsFixed(1);
    _out.writeln(
      'Synced: ${result.appliedChanges} change(s), '
      'now at ${result.newRef}$branch  (${secs}s).',
    );
    if (m.filesTransferred > 0) {
      _out.writeln(
        '  transferred: ${m.filesTransferred} file(s)  '
        '(${_humanBytes(m.bytesTransferred)} raw, '
        '${_humanBytes(m.bytesOnWire)} on-wire)',
      );
    }
    if (m.filesCopied > 0) {
      _out.writeln('  copied (dedup): ${m.filesCopied} file(s)');
    }
    if (m.filesRemoved > 0) {
      _out.writeln('  removed: ${m.filesRemoved} file(s)');
    }
    if (verbose) {
      _listPaths('transferred', m.transferredPaths);
      _listPaths('copied', m.copiedPaths);
      _listPaths('removed', m.removedPaths);
    }
  }

  void _maybeRender({bool force = false}) {
    final now = DateTime.now();
    if (!force && now.difference(_lastRender).inMilliseconds < 80) return;
    _renderLive();
    _lastRender = now;
  }

  void _renderLive() {
    const maxBars = 12;
    final buf = StringBuffer();
    if (_renderedLines > 0) buf.write('\x1b[${_renderedLines}A');
    buf.write('\x1b[0J'); // clear from cursor to end of screen
    var lines = 0;
    final items = _active.entries.toList();
    for (final e in items.take(maxBars)) {
      buf.writeln(_itemLine(e.key, e.value));
      lines++;
    }
    if (items.length > maxBars) {
      buf.writeln('  …and ${items.length - maxBars} more');
      lines++;
    }
    buf.writeln('  $_completed/$_total files  •  ${_humanBytes(_bytes)} sent');
    lines++;
    _out.write(buf.toString());
    _renderedLines = lines;
  }

  void _clearLiveBlock() {
    if (_renderedLines > 0) {
      _out.write('\x1b[${_renderedLines}A\x1b[0J');
      _renderedLines = 0;
    }
  }

  String _itemLine(String path, _Item it) {
    final copy = it.kind == ProgressItemKind.copied;
    final label = copy ? 'copy' : 'xfer';
    // A server-side copy sends no bytes, so its bar is indeterminate.
    final frac = copy ? null : it.fraction;
    final pct = frac == null
        ? ' --%'
        : '${(frac * 100).round().toString().padLeft(3)}%';
    final size = it.size != null ? ' (${_humanBytes(it.size!)})' : '';
    return '  $label ${_bar(frac)} $pct  ${_ellipsize(path, 44)}$size';
  }

  void _printPlainCompletion(String path, ProgressEvent e) {
    final label = switch (e.itemKind) {
      ProgressItemKind.copied => 'copied',
      ProgressItemKind.removed => 'removed',
      _ => 'transferred',
    };
    final size = e.itemSize != null ? ' (${_humanBytes(e.itemSize!)})' : '';
    _out.writeln('  $label  $path$size');
  }

  void _listPaths(String label, List<String> paths) {
    if (paths.isEmpty) return;
    _out.writeln('  $label:');
    for (final path in paths) {
      _out.writeln('    $path');
    }
  }

  static String _bar(double? frac, {int width = 20}) {
    if (frac == null) return '[${'-' * width}]';
    final filled = (frac * width).round().clamp(0, width);
    return '[${'#' * filled}${'-' * (width - filled)}]';
  }

  static String _ellipsize(String s, int max) =>
      s.length <= max ? s : '…${s.substring(s.length - max + 1)}';

  static String _humanBytes(int n) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var size = n.toDouble();
    var u = 0;
    while (size >= 1024 && u < units.length - 1) {
      size /= 1024;
      u++;
    }
    return '${u == 0 ? size.toStringAsFixed(0) : size.toStringAsFixed(1)} '
        '${units[u]}';
  }
}

/// Snapshot of a single in-flight file's progress.
class _Item {
  final ProgressItemKind kind;
  final int? bytes;
  final int? totalBytes;
  final int? size;

  _Item({required this.kind, this.bytes, this.totalBytes, this.size});

  double? get fraction {
    final t = totalBytes;
    final b = bytes;
    if (t == null || b == null || t == 0) return null;
    return (b / t).clamp(0.0, 1.0);
  }
}
