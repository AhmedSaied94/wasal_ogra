// Regenerates lib/core/theme/tokens/design_tokens.dart from
// docs/design/tokens.json (specs/008.5-m21-design-refresh,
// contracts/design-tokens.md "Generation").
//
// Usage, from apps/mobile:
//   fvm dart run tool/design/gen_tokens.dart
//
// Exits 1 on a value it can't read, naming its key.
import 'dart:convert';
import 'dart:io';

import 'token_generator.dart';

void main() {
  final mobile = File.fromUri(Platform.script).parent.parent.parent;
  final source = File('${mobile.path}/../../docs/design/tokens.json');
  final target = File(
    '${mobile.path}/lib/core/theme/tokens/design_tokens.dart',
  );
  try {
    final json = jsonDecode(source.readAsStringSync()) as Map<String, Object?>;
    target.writeAsStringSync(formatTokens(generateTokens(json)));
    stdout.writeln('Wrote ${target.path}.');
  } on FormatException catch (e) {
    stderr.writeln('tokens.json: ${e.message}');
    exitCode = 1;
  }
}
