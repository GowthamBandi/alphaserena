// Serena Design System — drift-guard (M1). Option B enforcement backstop.
// Regenerates the token layer from serena.tokens.json (via the same generator)
// and asserts BYTE-EQUALITY with the committed generated/serena_tokens.g.dart.
// Fails (exit 1) if a generated token was hand-edited or a repo's copy drifted.
// Intended to run in CI (e.g. `dart test` step) in EACH repo.
//
// Usage: dart run tools/drift_guard.dart [tokensJson] [committedDart]

import 'dart:io';

void main(List<String> args) {
  // Repo-layout defaults; all overridable by args: [tokensJson] [committedDart] [generatorPath]
  final json = args.isNotEmpty ? args[0] : 'lib/core/theme/serena/serena.tokens.json';
  final committed = args.length > 1 ? args[1] : 'lib/core/theme/serena/serena_tokens.g.dart';
  final generator = args.length > 2 ? args[2] : 'tool/serena/generate_tokens.dart';
  final tmp = '$committed.driftcheck';

  // Regenerate via the canonical generator (same code path -> guaranteed parity logic).
  final r = Process.runSync('dart', [generator, json, tmp]);
  if (r.exitCode != 0) {
    stderr.writeln('DRIFT-GUARD: generator failed:\n${r.stderr}');
    exit(2);
  }
  final want = File(tmp).readAsStringSync();
  File(tmp).deleteSync();

  final committedFile = File(committed);
  if (!committedFile.existsSync()) {
    stderr.writeln('DRIFT-GUARD FAIL: committed file missing: $committed (run the generator).');
    exit(1);
  }
  final have = committedFile.readAsStringSync();

  if (have == want) {
    stdout.writeln('DRIFT-GUARD PASS ✓  ($committed matches serena.tokens.json, ${have.length} bytes)');
    exit(0);
  }
  // Report the first divergence for a fast diagnosis.
  final a = have.split('\n'), bl = want.split('\n');
  var line = 0;
  final n = a.length < bl.length ? a.length : bl.length;
  while (line < n && a[line] == bl[line]) line++;
  stderr.writeln('DRIFT-GUARD FAIL ✗  $committed diverges from the token source at line ${line + 1}:');
  stderr.writeln('  committed: ${line < a.length ? a[line] : "<eof>"}');
  stderr.writeln('  expected : ${line < bl.length ? bl[line] : "<eof>"}');
  stderr.writeln('Fix: edit serena.tokens.json (the source of truth), then regenerate — never hand-edit the generated file.');
  exit(1);
}
