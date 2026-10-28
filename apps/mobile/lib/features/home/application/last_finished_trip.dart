// The trip finished last in this run (specs/013-m08-home-result, research
// R3, data-model "What is stored"): the line Home follows. Memory only, so
// a restart falls back to the latest first finish.
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'last_finished_trip.g.dart';

@Riverpod(keepAlive: true)
class LastFinishedTrip extends _$LastFinishedTrip {
  @override
  String? build() => null;

  String? get tripId => state;

  /// Set by the result screen when a finished trip's result opens.
  set tripId(String? value) => state = value;
}
