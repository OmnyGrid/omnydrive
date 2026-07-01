import 'dart:io';

import '../../../domain/entities/git_divergence.dart';
import '../../../domain/value_objects/git_credential.dart';
import '../../../shared/errors/domain_exception.dart';

/// Result of a single `git` invocation.
class GitResult {
  final int exitCode;
  final String stdout;
  final String stderr;

  const GitResult(this.exitCode, this.stdout, this.stderr);

  bool get ok => exitCode == 0;
}

/// The single chokepoint for all interaction with the system `git` binary.
///
/// Every git operation in OmnyDrive goes through here, so the rest of the code
/// never spawns processes directly. Commit invocations inject a deterministic
/// identity so they succeed even on machines without a configured git user
/// (CI runners, fresh containers).
class GitCli {
  /// Path to the git executable.
  final String executable;

  /// Identity used for commits made by automation.
  final String authorName;
  final String authorEmail;

  const GitCli({
    this.executable = 'git',
    this.authorName = 'OmnyDrive',
    this.authorEmail = 'omnydrive@localhost',
  });

  /// Whether a working `git` binary is available. Used by tests to skip when
  /// git is not installed.
  static Future<bool> isAvailable({String executable = 'git'}) async {
    try {
      final res = await Process.run(executable, ['--version']);
      return res.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Runs git with [args]. Throws [ProviderException] on a non-zero exit unless
  /// [allowFailure] is set, in which case the [GitResult] is returned as-is.
  ///
  /// When [credential] is supplied, its `-c` config args are prepended and its
  /// environment overrides applied, so authentication is injected in this one
  /// chokepoint. `GIT_TERMINAL_PROMPT=0` is always set so a missing or wrong
  /// credential fails fast instead of hanging on an interactive prompt.
  Future<GitResult> run(
    List<String> args, {
    String? workingDirectory,
    bool allowFailure = false,
    GitCredential? credential,
  }) async {
    final result = await Process.run(
      executable,
      [...?credential?.configArgs(), ...args],
      workingDirectory: workingDirectory,
      environment: {'GIT_TERMINAL_PROMPT': '0', ...?credential?.envVars()},
      includeParentEnvironment: true,
    );
    final out = (result.stdout as String).trimRight();
    final err = (result.stderr as String).trimRight();
    if (result.exitCode != 0 && !allowFailure) {
      throw ProviderException(
        'git ${args.join(' ')} failed (${result.exitCode}): $err',
      );
    }
    return GitResult(result.exitCode, out, err);
  }

  // ---- Repository creation -------------------------------------------------

  Future<void> initBare(String path) => run(['init', '--bare', path]);

  Future<void> init(String path) => run(['init', path]);

  /// Clones [url] into [dest]. [branch] checks out a specific branch; [depth]
  /// performs a shallow clone (used for read-only/CI workflows); [bare] clones
  /// without a working tree.
  Future<void> clone(
    String url,
    String dest, {
    String? branch,
    int? depth,
    bool bare = false,
    GitCredential? credential,
  }) => run([
    'clone',
    if (bare) '--bare',
    if (depth != null) ...['--depth', '$depth'],
    if (branch != null) ...['--branch', branch],
    url,
    dest,
  ], credential: credential);

  // ---- References ----------------------------------------------------------

  /// Resolves [rev] (default `HEAD`) to a commit SHA in the repo at [path].
  Future<String> revParse(String path, {String rev = 'HEAD'}) async =>
      (await run(['rev-parse', rev], workingDirectory: path)).stdout.trim();

  /// The current branch name in the repo at [path].
  Future<String> currentBranch(String path) async => (await run([
    'rev-parse',
    '--abbrev-ref',
    'HEAD',
  ], workingDirectory: path)).stdout.trim();

  /// Looks up the SHA a [ref] points to on the remote [url]. Returns null when
  /// the ref does not exist.
  Future<String?> lsRemote(
    String url,
    String ref, {
    GitCredential? credential,
  }) async {
    final res = await run(['ls-remote', url, ref], credential: credential);
    if (res.stdout.isEmpty) return null;
    return res.stdout.split(RegExp(r'\s+')).first.trim();
  }

  /// Resolves the SHA of [branch] in the repo at [path] (works for bare repos).
  Future<String?> branchSha(String path, String branch) async {
    final res = await run(
      ['rev-parse', '--verify', '--quiet', 'refs/heads/$branch'],
      workingDirectory: path,
      allowFailure: true,
    );
    if (!res.ok || res.stdout.isEmpty) return null;
    return res.stdout.trim();
  }

  // ---- Mutations -----------------------------------------------------------

  Future<void> fetch(
    String path, {
    String remote = 'origin',
    GitCredential? credential,
  }) => run(['fetch', remote], workingDirectory: path, credential: credential);

  Future<void> checkoutNewBranch(String path, String branch) =>
      run(['checkout', '-b', branch], workingDirectory: path);

  Future<void> checkout(String path, String ref) =>
      run(['checkout', ref], workingDirectory: path);

  Future<void> addAll(String path) =>
      run(['add', '-A'], workingDirectory: path);

  /// Whether the working tree at [path] has staged or unstaged changes.
  Future<bool> hasChanges(String path) async {
    final res = await run(['status', '--porcelain'], workingDirectory: path);
    return res.stdout.trim().isNotEmpty;
  }

  /// Commits all staged changes with [message]. Returns the new commit SHA.
  Future<String> commit(String path, String message) async {
    await run([
      '-c',
      'user.name=$authorName',
      '-c',
      'user.email=$authorEmail',
      'commit',
      '-m',
      message,
    ], workingDirectory: path);
    return revParse(path);
  }

  /// Returns the relative paths changed between [from] and [to] in [path].
  Future<List<String>> changedFiles(
    String path, {
    required String from,
    required String to,
  }) async {
    final res = await run(
      ['diff', '--name-only', from, to],
      workingDirectory: path,
      allowFailure: true,
    );
    if (!res.ok || res.stdout.trim().isEmpty) return const [];
    return res.stdout.trim().split('\n').map((l) => l.trim()).toList();
  }

  /// Fast-forwards the current branch at [path] to [ref], failing if a
  /// fast-forward is not possible.
  Future<void> mergeFastForward(String path, String ref) =>
      run(['merge', '--ff-only', ref], workingDirectory: path);

  Future<void> push(
    String path,
    String branch, {
    String remote = 'origin',
    bool setUpstream = true,
    GitCredential? credential,
  }) => run(
    ['push', if (setUpstream) '-u', remote, branch],
    workingDirectory: path,
    credential: credential,
  );

  /// Computes ahead/behind divergence between [base] and [head] in [path].
  Future<GitDivergence> divergence(
    String path, {
    required String base,
    required String head,
  }) async {
    final res = await run([
      'rev-list',
      '--left-right',
      '--count',
      '$base...$head',
    ], workingDirectory: path);
    final parts = res.stdout.trim().split(RegExp(r'\s+'));
    final behind = int.tryParse(parts.isNotEmpty ? parts[0] : '0') ?? 0;
    final ahead = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
    return GitDivergence(
      ahead: ahead,
      behind: behind,
      baseSha: await revParse(path, rev: base),
      headSha: await revParse(path, rev: head),
    );
  }
}
