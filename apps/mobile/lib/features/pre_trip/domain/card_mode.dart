// Whether a start shows the pre-trip card (specs/013-m08-home-result,
// data-model `CardDecision`, research R6).
import 'package:content_models/content_models.dart';
import 'package:wassal/features/pre_trip/domain/briefing.dart';
import 'package:wassal/features/pre_trip/domain/met_set.dart';

/// A story trip always shows it, and so does a trip with something new;
/// otherwise only when the setting is [always].
bool shouldShowCard(TripDefinition trip, MetSet met, {required bool always}) =>
    trip.kind == TripKind.story || newSubjectOf(trip, met) != null || always;
