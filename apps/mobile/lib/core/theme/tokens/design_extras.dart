import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';

/// The values an artboard uses between tokens (HANDOFF §2.2: "use the HTML
/// value; don't round to the nearest token"). Hand-written: each names the
/// artboard and element it comes from (specs/008.5-m21-design-refresh,
/// contracts/design-tokens.md "Extras"). The list grows only from the
/// artboards' HTML.
///
/// The bubble and popover lips and the coach scrim are tokens
/// (`LipTokens.bubble`, `bubbleWarn`, `popover`; `ColorTokens.scrimCoach`),
/// so they aren't repeated here.
abstract final class DesignExtras {
  /// HANDOFF §2.4: the least top inset a screen keeps when the phone reports
  /// a smaller status bar (the design's 36 stands for the status bar).
  static const double minTopInset = 24;

  /// `Loading` block 1: the wordmark «وصّل الأجرة», Marhey 700 60, line 66.
  static const loadingWordmark = TextStyle(
    fontFamily: TypeTokens.marhey,
    fontSize: 60,
    fontWeight: FontWeight.w700,
    fontVariations: [FontVariation('wght', 700)],
    height: 1.1,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// `Loading` block 1: the wordmark's text shadow, `sun.lip` at (0, 5).
  static const loadingWordmarkShadow = Shadow(
    offset: Offset(0, 5),
    color: ColorTokens.sunLip,
  );

  /// `Loading` block 2: the tagline, Readex Pro 500 15 on the browser's
  /// normal line, measured 19.
  static const loadingTagline = TextStyle(
    fontFamily: TypeTokens.readexPro,
    fontSize: 15,
    fontWeight: FontWeight.w500,
    fontVariations: [FontVariation('wght', 500)],
    height: 19 / 15,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// `Loading` block 5: the line under the road bar, Readex Pro 600 16 on
  /// the browser's normal line, measured 20.
  static const loadingLine = TextStyle(
    fontFamily: TypeTokens.readexPro,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    fontVariations: [FontVariation('wght', 600)],
    height: 20 / 16,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// `Loading` block 3: the roof sign «الموقف», Marhey 700 15 in the
  /// vehicle art's units.
  static const loadingSign = TextStyle(
    fontFamily: TypeTokens.marhey,
    fontSize: 15,
    fontWeight: FontWeight.w700,
    fontVariations: [FontVariation('wght', 700)],
    height: 1,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// `Loading` block 3 (research R6): the vehicle drives in from the right.
  static const loadingVehicleIn = Duration(milliseconds: 600);
  static const loadingVehicleCurve = Curves.easeOutCubic;

  /// `Loading` block 4 (research R6): each progress update moves the
  /// marker linearly over at most this.
  static const roadStep = Duration(milliseconds: 150);
  static const roadStepCurve = Curves.linear;

  /// `Loading` block 4: the road marker's lip, `primary.lip` at (0, 3).
  static const roadMarkerLip = BoxShadow(
    offset: Offset(0, 3),
    color: ColorTokens.primaryLip,
  );

  /// `Pause` box 11: «كمّل المشوار», Marhey 700 23 on the 60-high button.
  static const pauseButtonLabel = TextStyle(
    fontFamily: TypeTokens.marhey,
    fontSize: 23,
    fontWeight: FontWeight.w700,
    fontVariations: [FontVariation('wght', 700)],
    height: 1,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// `Pause` box 11: the resume button's height.
  static const double pauseButtonHeight = 60;

  /// `Fail` box 10: «المشوار باظ», Marhey 700 30 on the browser's normal
  /// line, measured 52.
  static const failTitle = TextStyle(
    fontFamily: TypeTokens.marhey,
    fontSize: 30,
    fontWeight: FontWeight.w700,
    fontVariations: [FontVariation('wght', 700)],
    height: 52 / 30,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// `Pause` box 9: «واقفين على جنب», Marhey 700 28 on the browser's normal
  /// line, measured 49.
  static const pauseTitle = TextStyle(
    fontFamily: TypeTokens.marhey,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    fontVariations: [FontVariation('wght', 700)],
    height: 49 / 28,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// `Pause` box 10: the line under the title, Readex Pro 500 13 on the
  /// browser's normal line, measured 16.
  static const dialogSubtitle = TextStyle(
    fontFamily: TypeTokens.readexPro,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    fontVariations: [FontVariation('wght', 500)],
    height: 16 / 13,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// `C-Trip`: the next station's name on its sign in the window, Readex
  /// Pro 700 13, centred on the board (HANDOFF §11 "Next-station sign").
  static const stationSignName = TextStyle(
    fontFamily: TypeTokens.readexPro,
    fontSize: 13,
    fontWeight: FontWeight.w700,
    fontVariations: [FontVariation('wght', 700)],
    height: 1,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// `Fail` box 11: the reason chip's text, Readex Pro 600 13, measured 16.
  static const failReason = TextStyle(
    fontFamily: TypeTokens.readexPro,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    fontVariations: [FontVariation('wght', 600)],
    height: 16 / 13,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// `Fail` box 11: the reason chip's padding, 3 12.
  static const failReasonPadding = EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 3,
  );

  /// `Fail` box 18: a dialog's small line, Readex Pro 500 12, measured 15.
  static const dialogNote = TextStyle(
    fontFamily: TypeTokens.readexPro,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    fontVariations: [FontVariation('wght', 500)],
    height: 15 / 12,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// `Pause` box 7, `Fail` box 8: where the card's top sits on the
  /// reference frame.
  static const double pauseTop = 170;
  static const double failTop = 120;

  /// `Pause` box 7, `Fail` box 8: the cards' padding, 22 18 18 and 20 18 16.
  static const pausePadding = EdgeInsets.fromLTRB(18, 22, 18, 18);
  static const failPadding = EdgeInsets.fromLTRB(18, 20, 18, 16);

  /// `Pause` box 6: ink at 0.62 (the coach scrim's value). `Fail` uses
  /// `ColorTokens.scrimFail`.
  static const pauseScrim = ColorTokens.scrimCoach;

  /// `Pause` box 8: the parked microbus.
  static const Size pauseArt = Size(72, 56);

  /// `Fail` box 9: the angry faces' strip: three heads, the passenger art's
  /// 42-unit head at 0.62 centred at (40, 38) and (170, 38), and at 0.7 at
  /// (105, 34).
  static const Size failFaces = Size(210, 70);
  static const double failFaceSide = 42 * 0.62;
  static const double failFaceMiddle = 42 * 0.7;
  static const double failFaceSideX = 65;
  static const double failFaceSideY = 38;
  static const double failFaceMiddleY = 34;

  /// `Fail` boxes 19 and 21: the restart and home tiles, `ground`, 48 high,
  /// radius 16.
  static const double failTileHeight = 48;
  static const double failTileRadius = 16;

  /// `States` box 14: the spend confirmation's «أيوه», Marhey 700 19 on a
  /// 52-high, radius-18 button; «لأ» beside it on `ground` (box 15).
  static const confirmLabel = TextStyle(
    fontFamily: TypeTokens.marhey,
    fontSize: 19,
    fontWeight: FontWeight.w700,
    fontVariations: [FontVariation('wght', 700)],
    height: 1.2,
    leadingDistribution: TextLeadingDistribution.even,
  );
  static const double confirmHeight = 52;

  /// `States` box 12: the spend confirmation's question, Marhey 700 22 on
  /// the browser's normal line, measured 38.
  static const confirmTitle = TextStyle(
    fontFamily: TypeTokens.marhey,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    fontVariations: [FontVariation('wght', 700)],
    height: 38 / 22,
    leadingDistribution: TextLeadingDistribution.even,
  );
  static const double confirmRadius = 18;

  /// `States` box 21: an error card's title, Marhey 700 18 on the
  /// browser's normal line, measured 32.
  static const errorTitle = TextStyle(
    fontFamily: TypeTokens.marhey,
    fontSize: 18,
    fontWeight: FontWeight.w700,
    fontVariations: [FontVariation('wght', 700)],
    height: 32 / 18,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// `States` boxes 28, 33: an update or maintenance card's title, Marhey
  /// 700 17 on the browser's normal line, measured 30.
  static const statusTitle = TextStyle(
    fontFamily: TypeTokens.marhey,
    fontSize: 17,
    fontWeight: FontWeight.w700,
    fontVariations: [FontVariation('wght', 700)],
    height: 30 / 17,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// `States` box 37: an empty list's message, Readex Pro 600 14, measured
  /// 18.
  static const emptyMessage = TextStyle(
    fontFamily: TypeTokens.readexPro,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    fontVariations: [FontVariation('wght', 600)],
    height: 18 / 14,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// `States` box 11: the spend confirmation's picture.
  static const double confirmArt = 44;

  /// `C-Trip` box 3: the line and trip title, Marhey 700 18 on a 19.8 line.
  static const hudTitle = TextStyle(
    fontFamily: TypeTokens.marhey,
    fontSize: 18,
    fontWeight: FontWeight.w700,
    fontVariations: [FontVariation('wght', 700)],
    height: 1.1,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// `Pause` box 7, `Fail` box 8: the dialog card's radius.
  static const double dialogRadius = 26;

  /// `Pause` box 7: the dialog's padding (content at x 34 in a card at 16).
  static const double dialogPadding = 18;

  /// `Components` box 164 (HANDOFF §3.3 `EventBanner`): the banner title,
  /// Marhey 700 17.
  static const bannerTitle = TextStyle(
    fontFamily: TypeTokens.marhey,
    fontSize: 17,
    fontWeight: FontWeight.w700,
    fontVariations: [FontVariation('wght', 700)],
    height: 1.2,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// `Pause` box 12, `Fail` box 16: a dialog's secondary button label,
  /// Readex Pro 700 17.
  static const dialogSecondaryLabel = TextStyle(
    fontFamily: TypeTokens.readexPro,
    fontSize: 17,
    fontWeight: FontWeight.w700,
    fontVariations: [FontVariation('wght', 700)],
    height: 1.2,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// `Pause` box 12, `Fail` box 16: the dialog's secondary button radius.
  static const double dialogSecondaryRadius = 18;

  /// `Components` box 15: the 64-high danger button's label, Marhey 700 25.
  static const dangerButtonLabel = TextStyle(
    fontFamily: TypeTokens.marhey,
    fontSize: 25,
    fontWeight: FontWeight.w700,
    fontVariations: [FontVariation('wght', 700)],
    height: 1,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// `Components` box 17, 153, 132: 44-high controls (the sun call button,
  /// the choice buttons, tray cells), Readex Pro 700 14.
  static const compactLabel = TextStyle(
    fontFamily: TypeTokens.readexPro,
    fontSize: 14,
    fontWeight: FontWeight.w700,
    fontVariations: [FontVariation('wght', 700)],
    height: 1.2,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// `Components` box 8, 19: the 54–58 button's height on the board.
  static const double buttonLHeight = 56;

  /// `Components` box 17: the 44-high sun button's radius.
  static const double compactButtonRadius = 16;

  /// `Components` box 21, `Pause` box 15: the tertiary button, Readex Pro
  /// 700 15.
  static const tertiaryLabel = TextStyle(
    fontFamily: TypeTokens.readexPro,
    fontSize: 15,
    fontWeight: FontWeight.w700,
    fontVariations: [FontVariation('wght', 700)],
    height: 1.35,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// `Components` box 12: the rewarded-ad button's title, Marhey 700 22.
  static const rewardedTitle = TextStyle(
    fontFamily: TypeTokens.marhey,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    fontVariations: [FontVariation('wght', 700)],
    height: 1.15,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// `Components` box 10: the rewarded-ad button's height.
  static const double rewardedHeight = 66;

  /// `Components` box 4: the cost chip on a 64-high button, 30 high
  /// (HANDOFF §3.1 says 32; the artboard wins).
  static const double costChipHeight = 30;

  /// `Components` box 28, 113: a pill's value and a money note's digits,
  /// Readex Pro 700 16.
  static const pillNumber = TextStyle(
    fontFamily: TypeTokens.readexPro,
    fontSize: 16,
    fontWeight: FontWeight.w700,
    fontVariations: [FontVariation('wght', 700)],
    height: 1.1,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// `Components` box 34: the fuel pill's «٤/٥», Readex Pro 700 15.
  static const pillFuel = TextStyle(
    fontFamily: TypeTokens.readexPro,
    fontSize: 15,
    fontWeight: FontWeight.w700,
    fontVariations: [FontVariation('wght', 700)],
    height: 1.05,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// `Components` box 35: the fuel pill's refill timer, Readex Pro 500 12.
  static const pillTimer = TextStyle(
    fontFamily: TypeTokens.readexPro,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    fontVariations: [FontVariation('wght', 500)],
    height: 1.05,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// `Components` box 42–46: chips and badges, Readex Pro 700 12.
  static const chipLabel = TextStyle(
    fontFamily: TypeTokens.readexPro,
    fontSize: 12,
    fontWeight: FontWeight.w700,
    fontVariations: [FontVariation('wght', 700)],
    height: 1.25,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// `Components` box 56–60: a segment's label, Readex Pro 600 13 (700 when
  /// active).
  static const segmentLabel = TextStyle(
    fontFamily: TypeTokens.readexPro,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    fontVariations: [FontVariation('wght', 600)],
    height: 1.2,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// `Components` box 61: a text field's text, Readex Pro 600 18.
  static const fieldText = TextStyle(
    fontFamily: TypeTokens.readexPro,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    fontVariations: [FontVariation('wght', 600)],
    height: 1.3,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// `Components` box 176–184: a tab's label, Readex Pro 600 13 (700 when
  /// active).
  static const navLabel = TextStyle(
    fontFamily: TypeTokens.readexPro,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    fontVariations: [FontVariation('wght', 600)],
    height: 1.2,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// `Components` box 177: the active tab's pill.
  static const Size navPill = Size(60, 34);

  /// `Components` box 166: the offline banner's text, Readex Pro 600 12.5.
  static const offlineText = TextStyle(
    fontFamily: TypeTokens.readexPro,
    fontSize: 12.5,
    fontWeight: FontWeight.w600,
    fontVariations: [FontVariation('wght', 600)],
    height: 1.3,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// `Components` box 171: a sheet's title, Marhey 700 22.
  static const sheetTitle = TextStyle(
    fontFamily: TypeTokens.marhey,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    fontVariations: [FontVariation('wght', 700)],
    height: 1.2,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// `Intro` box 8: a comic panel's line, Marhey 600 19 at 1.45.
  static const comicLine = TextStyle(
    fontFamily: TypeTokens.marhey,
    fontSize: 19,
    fontWeight: FontWeight.w600,
    fontVariations: [FontVariation('wght', 600)],
    height: 1.45,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// `Components` box 170: the sheet's grabber.
  static const Size sheetGrabber = Size(44, 5);

  /// `Components` box 175: the bottom nav's top radius (26 on the board).
  static const double navRadius = 26;

  /// `Components` box 66: the reputation bar's track.
  /// `C-Trip` box 5: the reputation bar, 92×12 (HANDOFF says 90×10; the
  /// artboard wins).
  static const Size reputationBar = Size(92, 12);

  /// `C-Trip` box 61: «حد معاه فكة؟» beside the hand, at its board width.
  static const double callChangeWidth = 151.5;

  /// `Components` box 84, 86, 88: a station tag's letter on the back (24),
  /// middle (26) and near (30) rows.
  static const double tagLetterBack = 13;
  static const double tagLetterMiddle = 14;
  static const double tagLetterNear = 16;

  /// `Components` box 74: a strip dot's letter, 12 on a 24 dot.
  static const double stripLetterSize = 12;

  /// `Components` box 99: a bubble's padding, 3 14 5 (HANDOFF §3.4).
  static const EdgeInsets bubblePadding = EdgeInsets.fromLTRB(14, 3, 14, 5);

  /// `Components` box 100: a bubble's tail, a 14 square turned 45°.
  static const double bubbleTail = 14;
  static const double bubbleTailRadius = 4;

  /// `Components` box 113: a money note's radius and minimum size.
  static const double noteRadius = 7;
  static const Size noteMin = Size(42, 26);

  /// `Components` box 128: a mini note in the hand slot, radius 5.
  static const double miniNoteRadius = 5;

  /// `Components` box 120: a fallen note's ring, `sun.glow`, 4 wide.
  static const double fallenRingWidth = 4;
  static const fallenRing = RingSpec(
    width: fallenRingWidth,
    color: ColorTokens.sunGlow,
    inside: false,
    dashed: false,
  );

  /// `Components` box 113: a money note's lip, 3 down in its kind's lip
  /// colour.
  static BoxShadow noteLip(Color color) =>
      BoxShadow(offset: const Offset(0, 3), color: color);

  /// `Components` box 116, `C-Trip` box 47: the «؟» badge over a blocked
  /// note, 22 across, 23 above it.
  static const double noteBadge = 22;
  static const double noteBadgeRise = 23;

  /// `C-Trip` box 55 and `Components` box 120: the note in the driver's
  /// hand leans −18°, a fallen one 12°.
  static const double inHandTilt = -18 * 3.141592653589793 / 180;
  static const double fallenTilt = 12 * 3.141592653589793 / 180;

  /// `C-Trip` box 55: the note in hand sits this far from the palm.
  static const Offset inHandFromPalm = Offset(14, -23);

  /// `C-Trip` boxes 26–35: a station tag's white border and its drop.
  static const double tagBorder = 2.5;
  static const tagLip = BoxShadow(
    offset: Offset(0, 2),
    color: Color(0x401D1A2B),
  );

  /// `TripEvents`: the event banner's lip, `0 4 danger.ink`.
  static const eventBannerLip = BoxShadow(
    offset: Offset(0, 4),
    color: ColorTokens.dangerInk,
  );

  /// The text style under an overlay, which has no screen's `Scaffold`
  /// above it to give one: Readex Pro 500 14 in ink, undecorated.
  static const overlayText = TextStyle(
    fontFamily: TypeTokens.readexPro,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: ColorTokens.ink,
    decoration: TextDecoration.none,
  );

  /// HANDOFF §3.4: the fight bubble's lip, `0 4 danger.ink`.
  static const bubbleFightLip = BoxShadow(
    offset: Offset(0, 4),
    color: ColorTokens.dangerInk,
  );

  /// `TripEvents` block 6: «لأ، ما دفعتش!»'s lip, `0 3 danger.ink`.
  static const choiceDangerLip = BoxShadow(
    offset: Offset(0, 3),
    color: ColorTokens.dangerInk,
  );

  /// `TripEvents` block 6, `Components`: a `ChoicePopover` and its buttons.
  static const double popoverRadius = 18;
  static const double popoverPadding = 5;
  static const double choiceRadius = 14;
  static const TextStyle choiceLabel = TextStyle(
    fontFamily: TypeTokens.readexPro,
    fontSize: 15,
    fontWeight: FontWeight.w700,
    fontVariations: [FontVariation('wght', 700)],
  );

  /// `TripEvents` block 9: a booster at work wears a `sun` ring this wide.
  static const double boosterActiveRing = 2;

  /// `TripEvents` block 5: a `LedgerBadge`, 18 high.
  static const double ledgerBadgeHeight = 18;

  /// `Tutorial` box 2b: a character's bubble, padding 10/16/12, radius 20.
  static const EdgeInsets characterBubblePadding = EdgeInsets.fromLTRB(
    16,
    10,
    16,
    12,
  );
  static const double characterBubbleRadius = 20;

  /// `Tutorial` block 5: بلية's hint bubble, padding 10/14/12, his line in
  /// `quote` at 18 / 1.45, its tail a 16 pt square 22 up the end edge.
  static const EdgeInsets hintBubblePadding = EdgeInsets.fromLTRB(
    14,
    10,
    14,
    12,
  );
  static const TextStyle hintQuote = TextStyle(
    fontFamily: TypeTokens.marhey,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    fontVariations: [FontVariation('wght', 600)],
    height: 1.45,
    leadingDistribution: TextLeadingDistribution.even,
  );
  static const double hintTail = 16;
  static const double hintTailRadius = 5;
  static const double hintTailRise = 22;

  /// `C-Trip` box 36 (`hurried.svg`): the sweat drop the static art paints
  /// on a frowning passenger.
  static const passengerSweat = Color(0xFF7CC5E8);

  /// `C-Trip` and `Tutorial`: the buildings seen through the windows.
  static const sceneBuildings = <Color>[
    Color(0xFFF9C79E),
    Color(0xFFF4B7A0),
    Color(0xFFD6CDF0),
    ColorTokens.denom200,
  ];

  /// `C-Trip` and `Tutorial`: the driver's hand and its thumb.
  static const driverSkin = Color(0xFFE0A97A);
  static const driverThumb = Color(0xFFD69A6C);

  // Code motion from HANDOFF §6.5 that tokens.json doesn't carry.

  /// Progress bars: a width tween on each change.
  static const progressTween = Duration(milliseconds: 500);
  static const progressCurve = Curves.easeOutCubic;

  /// `NewDot` appearing: scale 0 → 1.2 → 1.
  static const newDotIn = Duration(milliseconds: 240);

  /// `BottomNav`: the cross-fade between tabs.
  static const tabFade = Duration(milliseconds: 150);

  /// The trip's countdown chip, pulsing under 8 s.
  static const countdownPulse = Duration(milliseconds: 500);

  /// Banners hold 4 s before hiding (the toast's hold is a token).
  static const bannerHold = Duration(seconds: 4);

  /// The longest fade reduced motion allows (HANDOFF §6.5).
  static const reducedFade = Duration(milliseconds: 150);

  /// M03 FR-022's page fade-through, which the design keeps (it has no
  /// page-transition token): the outgoing page fades over the first 30%,
  /// then the incoming one fades in and grows from 0.92.
  static const pageTransition = Duration(milliseconds: 250);
  static const pageEnterCurve = Interval(0.3, 1, curve: Curves.easeOut);
  static const pageExitCurve = Interval(0, 0.3, curve: Curves.easeIn);
  static const double pageGrowFrom = 0.92;

  /// A switch's knob sliding across; no artboard animates it, so it takes
  /// the tab fade's 150 ms.
  static const switchKnob = tabFade;

  /// `Intro` motion (HANDOFF): under reduced motion a panel change is a
  /// fade of at most 150 ms.
  static const panelFadeReduced = Duration(milliseconds: 150);

  /// `Intro` box 2: «تخطّى», Readex Pro 600 14 on its 44-high pill.
  static const skipLabel = TextStyle(
    fontFamily: TypeTokens.readexPro,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    fontVariations: [FontVariation('wght', 600)],
    height: 1.2,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// `Name` motion (HANDOFF): the dice swaps the field's name in 150 ms.
  static const nameDiceSwap = Duration(milliseconds: 150);

  /// `Name` boxes 6, 7 and 11: the subtitle (Readex Pro 500 14), the field
  /// label (600 13) and the helper (500 12), on the browser's normal line,
  /// measured 18, 16 and 15.
  static const nameSubtitle = TextStyle(
    fontFamily: TypeTokens.readexPro,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    fontVariations: [FontVariation('wght', 500)],
    height: 18 / 14,
    leadingDistribution: TextLeadingDistribution.even,
  );
  static const nameLabel = TextStyle(
    fontFamily: TypeTokens.readexPro,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    fontVariations: [FontVariation('wght', 600)],
    height: 16 / 13,
    leadingDistribution: TextLeadingDistribution.even,
  );
  static const nameHelper = TextStyle(
    fontFamily: TypeTokens.readexPro,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    fontVariations: [FontVariation('wght', 500)],
    height: 15 / 12,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// The Name sheet's refused line (contracts/name.md "The re-ask"): Readex
  /// Pro 600 14, in `danger.ink`.
  static const nameRefused = TextStyle(
    fontFamily: TypeTokens.readexPro,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    fontVariations: [FontVariation('wght', 600)],
    height: 1.5,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// `Name` box 8: the name field, 54 high, its text Readex Pro 600 20.
  static const double nameFieldHeight = 54;
  static const nameFieldText = TextStyle(
    fontFamily: TypeTokens.readexPro,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    fontVariations: [FontVariation('wght', 600)],
    height: 1.2,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// `Name` box 9: the dice button, 54 square, its lip 4 down in
  /// `sun.soft.lip` (HANDOFF proposes the token).
  static const double nameDice = 54;
  static const nameDiceLip = LipTokens.sunSoft;

  /// `Name` box 12: «تمام», Marhey 700 25 on a 60-high button.
  static const nameCtaLabel = TextStyle(
    fontFamily: TypeTokens.marhey,
    fontSize: 25,
    fontWeight: FontWeight.w700,
    fontVariations: [FontVariation('wght', 700)],
    height: 1,
    leadingDistribution: TextLeadingDistribution.even,
  );
  static const double nameCtaHeight = 60;

  /// `Name` boxes 2–3: the card's padding, 76 20 22, and the avatar's
  /// 112 circle overlapping its top by 56, lip 5 in `sun.lip`.
  static const nameCardPadding = EdgeInsets.fromLTRB(20, 76, 20, 22);
  static const double nameAvatar = 112;
  static const double nameAvatarArt = 104;
  static const nameAvatarLip = BoxShadow(
    offset: Offset(0, 5),
    color: ColorTokens.sunLip,
  );

  /// `Name` box 1: the two `primary.soft` circles behind the card, as
  /// (centre, radius) on the 390×844 board.
  static const nameCircles = [
    (Offset(340, 90), 90.0),
    (Offset(30, 760), 120.0),
  ];

  /// `FuelLesson` box 10: the gauge, 220×124. Its arc, r 72 and 22 wide, is
  /// on the hub at (110, 94); the needle, 7 wide on a 12 hub, reaches
  /// [fuelLessonNeedleTip] at full and its mirror at empty.
  static const fuelLessonGauge = Size(220, 124);
  static const fuelLessonHub = Offset(110, 94);
  static const double fuelLessonRadius = 72;
  static const double fuelLessonArc = 22;
  static const double fuelLessonNeedle = 7;
  static const fuelLessonNeedleTip = Offset(60, -26);
  static const double fuelLessonHubRadius = 12;

  /// Rive's `FuelGauge` (156×110, its arc r 48 on the hub at 78, 92) at
  /// 1.5×, placed in the gauge's box so its arc lies on the board's.
  static const fuelLessonArt = Rect.fromLTWH(-7, -44, 234, 165);

  /// The pump inside the arc, centred this far above the hub.
  static const double fuelLessonPump = 32;
  static const double fuelLessonPumpRise = 40;

  /// The E and F marks under the arc's ends, Readex Pro 700 15.
  static const fuelLessonMark = TextStyle(
    fontFamily: TypeTokens.readexPro,
    fontSize: 15,
    fontWeight: FontWeight.w700,
    fontVariations: [FontVariation('wght', 700)],
    height: 1.2,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// Box 11: the value 2 under the gauge, `number.l` on a 24 line.
  static const fuelLessonValue = TextStyle(
    fontFamily: TypeTokens.readexPro,
    fontSize: 20,
    fontWeight: FontWeight.w700,
    fontVariations: [FontVariation('wght', 700)],
    height: 1.2,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// Box 12: the refill line, `body` (Readex Pro 500 14) on the browser's
  /// normal line, measured 18.
  static const fuelLessonRefill = TextStyle(
    fontFamily: TypeTokens.readexPro,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    fontVariations: [FontVariation('wght', 500)],
    height: 18 / 14,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// The needle's sweep to full, after the card has come in.
  static const fuelLessonSweep = Duration(milliseconds: 600);
  static const fuelLessonSweepCurve = Curves.easeOutCubic;

  // M08's motion that HANDOFF gives no value for
  // (specs/013-m08-home-result, research R13, R19).

  /// `C-Home` box 17: the barker's bubble pops again this often (R13).
  static const barkerRepop = Duration(seconds: 6);

  /// `Result` box 40: the pay counts up from 0 (R19).
  static const payCountUp = Duration(milliseconds: 600);

  /// `Result` boxes 52–54: the apartment bar fills from the old balance to the
  /// new, after the pay (R19).
  static const aptBarFill = Duration(milliseconds: 600);
  static const aptBarFillCurve = Curves.easeOut;

  /// `Result` box 8: each star's condition fades in with its star, this far
  /// apart: `Stars`' 16 frames at 60 fps (R19).
  static const starLabelStagger = Duration(milliseconds: 270);

  /// `Result` block 5: the quote fades in when its replay ends, as the
  /// banner does (R19's 200 ms).
  static const resultFadeIn = Duration(milliseconds: 200);
  static const resultFadeInCurve = Curves.easeOut;

  /// `C-Home` block 2 (`C-Home_02.svg`): the street's five buildings, left
  /// to right, in the trip's window colours.
  static const homeBuildings = <Color>[
    ColorTokens.denom200,
    Color(0xFFF4B7A0),
    Color(0xFFD6CDF0),
    Color(0xFFF9C79E),
    ColorTokens.denom200,
  ];

  /// `C-Home` block 2: the buildings' windows.
  static const homeWindow = Color(0xD9FFFFFF);

  /// `C-Home` block 2: the road's lane dashes.
  static const homeLane = Color(0xCCFFFFFF);

  /// `HomeStates` "Motion": the start button's variants cross-fade.
  static const ctaSwap = Duration(milliseconds: 150);

  /// `HomeStates` "Motion": the scene card's height follows the offline
  /// banner.
  static const homeSceneResize = Duration(milliseconds: 200);
  static const homeSceneResizeCurve = Curves.easeOut;

  /// `C-Home` box 4: the driver's name on Home, Marhey 700 19 (HANDOFF
  /// lists it as a non-token value).
  static const homeName = TextStyle(
    fontFamily: TypeTokens.marhey,
    fontSize: 19,
    fontWeight: FontWeight.w700,
    fontVariations: [FontVariation('wght', 700)],
    height: 1.2,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// `PreTrip` box 10: the card's title, Marhey 700 26, measured 31.2.
  static const preTripTitle = TextStyle(
    fontFamily: TypeTokens.marhey,
    fontSize: 26,
    fontWeight: FontWeight.w700,
    fontVariations: [FontVariation('wght', 700)],
    height: 1.2,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// `PreTrip` box 33: the new subject's name, Marhey 700 17 measured 30,
  /// as a status card's title.
  static const newCardName = statusTitle;

  /// `PreTrip` box 9: the line over the card's title, 13/600 on the
  /// browser's normal line, measured 16.
  static const preTripLine = TextStyle(
    fontFamily: TypeTokens.readexPro,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    fontVariations: [FontVariation('wght', 600)],
    height: 16 / 13,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// `PreTrip` boxes 17, 21, 25: a price cell's station, 13/600 on a
  /// 15.6 line.
  static const preTripStation = TextStyle(
    fontFamily: TypeTokens.readexPro,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    fontVariations: [FontVariation('wght', 600)],
    height: 1.2,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// `PreTrip` boxes 18, 22, 26: a price cell's fare, 16/700 on a 19.2
  /// line.
  static const preTripFare = TextStyle(
    fontFamily: TypeTokens.readexPro,
    fontSize: 16,
    fontWeight: FontWeight.w700,
    fontVariations: [FontVariation('wght', 700)],
    height: 1.2,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// `PreTrip` box 34: the new card's sentence, 13/500 on a 19.5 line.
  static const newCardText = TextStyle(
    fontFamily: TypeTokens.readexPro,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    fontVariations: [FontVariation('wght', 500)],
    height: 1.5,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// `Result` box 3: the header's «المشوار ١٢ · خط الجامعة», 14/600 on the
  /// browser's normal line, measured 18.
  static const resultHeader = TextStyle(
    fontFamily: TypeTokens.readexPro,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    fontVariations: [FontVariation('wght', 600)],
    height: 18 / 14,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// `Result` box 7: «وصلنا الجامعة!», `display.xl` on a 40 line.
  static const resultTitle = TextStyle(
    fontFamily: TypeTokens.marhey,
    fontSize: 32,
    fontWeight: FontWeight.w700,
    fontVariations: [FontVariation('wght', 700)],
    height: 40 / 32,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// `Result` boxes 24–31, 33, 37: the breakdown's and the mistakes' rows,
  /// 14/500 (the values and the summary 700) on an 18 line.
  static const resultRow = TextStyle(
    fontFamily: TypeTokens.readexPro,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    fontVariations: [FontVariation('wght', 500)],
    height: 18 / 14,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// `Result` boxes 10, 13, 16: the stars' labels, 12/600 on a 15 line.
  static const resultStarLabel = TextStyle(
    fontFamily: TypeTokens.readexPro,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    fontVariations: [FontVariation('wght', 600)],
    height: 15 / 12,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// `ShareCard` box 2: the trip chip, 13/600.
  static const shareChip = TextStyle(
    fontFamily: TypeTokens.readexPro,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    fontVariations: [FontVariation('wght', 600)],
    height: 16 / 13,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// `ShareCard` box 3: the title, Marhey 700 34 on `sun.lip`'s 4.
  static const shareTitle = TextStyle(
    fontFamily: TypeTokens.marhey,
    fontSize: 34,
    fontWeight: FontWeight.w700,
    fontVariations: [FontVariation('wght', 700)],
    height: 1.15,
    leadingDistribution: TextLeadingDistribution.even,
    shadows: [Shadow(offset: Offset(0, 4), color: ColorTokens.sunLip)],
  );

  /// `ShareCard` box 11: the quote, Marhey 600 16.
  static const shareQuote = TextStyle(
    fontFamily: TypeTokens.marhey,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    fontVariations: [FontVariation('wght', 600)],
    height: 1.35,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// `ShareCard` box 13: the wordmark, Marhey 700 20.
  static const shareWordmark = TextStyle(
    fontFamily: TypeTokens.marhey,
    fontSize: 20,
    fontWeight: FontWeight.w700,
    fontVariations: [FontVariation('wght', 700)],
    height: 35 / 20,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// `ShareCard` box 14: «قبضت {amount}», 13/700.
  static const sharePaid = TextStyle(
    fontFamily: TypeTokens.readexPro,
    fontSize: 13,
    fontWeight: FontWeight.w700,
    fontVariations: [FontVariation('wght', 700)],
    height: 16 / 13,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// `Result` box 38: «قبضت», 16/600.
  static const resultPayLabel = TextStyle(
    fontFamily: TypeTokens.readexPro,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    fontVariations: [FontVariation('wght', 600)],
    height: 20 / 16,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// `Result` box 40: the pay, Marhey 700 50 on a 50 line.
  static const resultPay = TextStyle(
    fontFamily: TypeTokens.marhey,
    fontSize: 50,
    fontWeight: FontWeight.w700,
    fontVariations: [FontVariation('wght', 700)],
    height: 1,
    leadingDistribution: TextLeadingDistribution.even,
  );
}

/// A ring as decoration: an outside one spreads a shadow past the edge, an
/// inside one is a border.
extension RingSpecDecoration on RingSpec {
  BoxShadow get spread => BoxShadow(color: color, spreadRadius: width);

  BoxBorder get border => Border.all(
    color: color,
    width: width,
    strokeAlign: inside
        ? BorderSide.strokeAlignInside
        : BorderSide.strokeAlignOutside,
  );
}

/// Sets a style's weight both ways, so the variable fonts' `wght` axis
/// follows it (as every type token does).
extension TextStyleWeight on TextStyle {
  TextStyle weight(int value) => copyWith(
    fontWeight: FontWeight.values[(value ~/ 100) - 1],
    fontVariations: [FontVariation('wght', value.toDouble())],
  );
}
