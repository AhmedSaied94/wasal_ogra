import 'dart:io';

/// The Dart files under `lib/` that repo checks scan, generated
/// localizations excluded.
Iterable<File> libDartFiles() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .where(
      (f) => !f.path.replaceAll(r'\', '/').contains('lib/l10n/generated/'),
    );

/// [source] with every comment blanked out. Strings are kept, and so are
/// newlines, so line numbers still match the file.
String stripComments(String source) {
  final out = StringBuffer();
  var i = 0;
  String? quote; // the delimiter of the string being read, if any
  var raw = false;
  bool at(String s) => source.startsWith(s, i);

  while (i < source.length) {
    final c = source[i];
    if (quote != null) {
      if (!raw && c == r'\' && i + 1 < source.length) {
        out.write(source.substring(i, i + 2));
        i += 2;
      } else if (at(quote)) {
        out.write(quote);
        i += quote.length;
        quote = null;
      } else {
        out.write(c);
        i++;
      }
    } else if (at('//')) {
      while (i < source.length && source[i] != '\n') {
        out.write(' ');
        i++;
      }
    } else if (at('/*')) {
      var depth = 0;
      do {
        if (at('/*')) {
          depth++;
          out.write('  ');
          i += 2;
        } else if (at('*/')) {
          depth--;
          out.write('  ');
          i += 2;
        } else {
          out.write(source[i] == '\n' ? '\n' : ' ');
          i++;
        }
      } while (depth > 0 && i < source.length);
    } else if (c == "'" || c == '"') {
      raw = i > 0 && (source[i - 1] == 'r' || source[i - 1] == 'R');
      quote = at("'''") || at('"""') ? c * 3 : c;
      out.write(quote);
      i += quote.length;
    } else {
      out.write(c);
      i++;
    }
  }
  return out.toString();
}
