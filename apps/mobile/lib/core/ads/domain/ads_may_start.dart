// When ads may start in the first session (specs/018-m11-ads, research R6,
// R15). Pure over M07's facts, which the checkpoint reads (analysis U2).

/// Whether ads may start (consent and the SDK) at this checkpoint: the
/// tutorial is done, or at least two of its trips are finished, so the next
/// start is tutorial trip 3 or later (spec Clarifications, analysis U2).
bool adsMayStart({required bool tutorialDone, required int tutorialFinished}) =>
    tutorialDone || tutorialFinished >= 2;
