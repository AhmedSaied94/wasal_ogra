// The «new» dot on «الخطوط» (specs/014-m09-lines-vehicles, contracts/
// lines.md "The «new» dot", FR-041): shown while something new on Lines
// hasn't been seen, from any tab, since a sync can bring news anywhere.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wassal/core/routing/new_dot_providers.dart';
import 'package:wassal/core/routing/routes.dart';
import 'package:wassal/features/lines/application/lines_seen.dart';

/// Created after `ContentLifecycle` in `bootstrap/app.dart`, and disposed
/// with it.
final class LinesDotWatcher {
  LinesDotWatcher(this._container) {
    _news = _container.listen(linesNewsKeysProvider, (_, _) => _update());
    _seen = _container.listen(linesSeenProvider, (_, _) => _update());
    _update();
  }

  final ProviderContainer _container;
  late final ProviderSubscription<Set<String>> _news;
  late final ProviderSubscription<Set<String>> _seen;

  void _update() {
    final unseen = _news.read().difference(_seen.read());
    final dot = _container.read(newDotProvider(Section.lines).notifier);
    if (unseen.isEmpty) {
      dot.clear();
    } else {
      dot.show();
    }
  }

  void dispose() {
    _news.close();
    _seen.close();
  }
}
