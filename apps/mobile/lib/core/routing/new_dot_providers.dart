import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wassal/core/routing/routes.dart';

part 'new_dot_providers.g.dart';

/// Whether a tab shows the «new» dot (FR-016a). Off until the feature that
/// owns the section calls [show]; opening the tab calls [clear].
@Riverpod(keepAlive: true)
class NewDotNotifier extends _$NewDotNotifier {
  @override
  bool build(Section section) => false;

  void show() => state = true;

  void clear() => state = false;
}
