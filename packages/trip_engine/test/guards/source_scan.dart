// Reads the engine's sources for the guard tests (research R16), with
// comments, and optionally string literals, removed.
import 'dart:io';

/// Every Dart file under `lib/`, sorted by path.
List<File> libSources() =>
    Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

/// [source] with `//` and `/* */` comments replaced by spaces. String
/// literals are kept, unless [strings] is false.
String stripped(String source, {bool strings = true}) {
  final out = StringBuffer();
  var i = 0;
  while (i < source.length) {
    if (source.startsWith('//', i)) {
      final end = source.indexOf('\n', i);
      i = end < 0 ? source.length : end;
    } else if (source.startsWith('/*', i)) {
      final end = source.indexOf('*/', i + 2);
      i = end < 0 ? source.length : end + 2;
      out.write(' ');
    } else if (_quoteAt(source, i) case final quote?) {
      final end = _stringEnd(source, i, quote);
      out.write(strings ? source.substring(i, end) : "''");
      i = end;
    } else {
      out.write(source[i]);
      i++;
    }
  }
  return out.toString();
}

// The opening quote at [i] (with any `r` prefix), or null.
String? _quoteAt(String source, int i) {
  final raw = source[i] == 'r' && !_isIdentifier(source, i - 1);
  final start = raw ? i + 1 : i;
  if (start >= source.length) return null;
  for (final quote in ["'''", '"""', "'", '"']) {
    if (source.startsWith(quote, start)) return raw ? 'r$quote' : quote;
  }
  return null;
}

bool _isIdentifier(String source, int i) =>
    i >= 0 && RegExp(r'[A-Za-z0-9_$]').hasMatch(source[i]);

// The index just past the string literal starting at [i]. Interpolations are
// kept inside the literal: the engine's interpolations never hold a quote.
int _stringEnd(String source, int i, String quote) {
  final raw = quote.startsWith('r');
  final delimiter = raw ? quote.substring(1) : quote;
  var j = i + quote.length;
  while (j < source.length) {
    if (!raw && source[j] == r'\') {
      j += 2;
    } else if (source.startsWith(delimiter, j)) {
      return j + delimiter.length;
    } else {
      j++;
    }
  }
  return source.length;
}

/// The URIs of every `import`, `export` and `part` directive in [source].
List<String> directiveUris(String source) => [
  for (final match in RegExp(
    r'''^\s*(?:import|export|part)\s+['"]([^'"]+)['"]''',
    multiLine: true,
  ).allMatches(stripped(source)))
    match.group(1)!,
];
