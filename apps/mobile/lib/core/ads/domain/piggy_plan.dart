// The morning piggy's asks for its grant (specs/018-m11-ads, research R12):
// after the reward, waits of 1, 2 and 4 s, so asks at 1, 3 and 7 s (SC-004).

const piggyWaitsMs = [1000, 2000, 4000];

/// What one lookup answered.
enum PiggyAnswer { granted, refused, notYet }

/// Where the asking stands after an answer.
enum PiggyStep { asking, granted, refused, gaveUp }

/// The step after [answer] to ask number [ask] (1-based).
PiggyStep piggyStep(PiggyAnswer answer, {required int ask}) => switch (answer) {
  PiggyAnswer.granted => PiggyStep.granted,
  PiggyAnswer.refused => PiggyStep.refused,
  PiggyAnswer.notYet =>
    ask >= piggyWaitsMs.length ? PiggyStep.gaveUp : PiggyStep.asking,
};
