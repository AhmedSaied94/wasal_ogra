# Contract: The Scene Viewer, the Timeline and the Album

How a scene plays after the first session and on every replay, how it is shared, and the two
screens that list the story. Research R4, R12, R13; spec FR-033–FR-039, Q3, Q5. The artboards'
values are in HANDOFF §11 (`SceneViewer`, `Chapters`, `Album`).

## Folders

```text
lib/features/story/
├── domain/        scene_sequence.dart, album.dart (pure)
├── application/   story_service.dart, story_due_watcher.dart, story_after_result.dart, story_providers.dart
└── presentation/  scene_viewer_page.dart, scene_panel_view.dart, scene_panel_share.dart, album_page.dart
lib/features/apartment/presentation/chapters_page.dart     (HANDOFF's folder for Chapters)
lib/core/platform/offscreen_render.dart                    (renderOffscreenPng, moved from result)
```

## Routes

| Route | Page | Plays | Unknown or nothing unlocked |
| --- | --- | --- | --- |
| `/story/scene/:sceneId?then=…` | `SceneViewerPage` | that scene, if unlocked | `then`, else `/apartment` |
| `/story/:chapterId?then=…` | `SceneViewerPage` | the chapter's unlocked scenes in story order, one after another | the same |
| `/story/album` | `AlbumPage` | — | — |
| `/apartment/chapters` | `ChaptersPage` (existing route, placeholder replaced) | — | — |

- Every page here is a root page with no `BottomNav`.
- `then` is validated as an in-app location (the router's existing `then` rule, M07).
- Back and «كمّل» go to `then` when given, else pop, else `/apartment`.

## The viewer (`SceneViewerPage`, research R12)

```dart
final class SceneSequence {            // domain, pure
  final List<(Chapter, Scene)> scenes; // one for /story/scene, the chapter's unlocked ones for /story/:chapterId
  int sceneIndex; int panelIndex;      // UI state, in the page's State
}
```

| Block | Rule |
| --- | --- |
| Top bar | «الفصل {n} · المشهد» over the scene's `title` (content); «تخطّى» pill, 44 high |
| Panel | `ScenePanelView`: M22's `PanelArt` (Rive when animated, else the drawing, else `PanelFallback`) in the 540 frame, with up to two `SpeechBubble`s (V-C12). The first sits at the start side, top 120, w190; the second at the end side, top 236, w180. The tail points down. A narrator line is M07's caption chip. Bubbles are clamped inside the panel |
| Speakers | ARB `sceneSpeaker(character)`; `usta` is the driver's name (`driverNameProvider`), «الأسطى» without one |
| Dots | M07's `PageDots`, one per panel of the current scene; they restart for the next scene |
| Last panel | «شارك» (flex 1) and «كمّل» (flex 2, primary xl); hidden on earlier panels, with the space kept |

**Taps:**

| Input | Result |
| --- | --- |
| Tap on the panel while its bubbles are still appearing | show them all at once |
| Tap on the panel, bubbles shown, not the last panel | next panel |
| Tap on the last panel | nothing (the buttons act) |
| «كمّل» on the last panel of a scene that isn't the sequence's last | record that scene, then the next scene's first panel |
| «كمّل» on the sequence's last panel | record, then leave |
| «تخطّى», system back | record every scene of the sequence reached so far, then leave |

- **Recording:** `StoryService.recordSeen(sceneId)` for each scene reached (story-flow.md). Reaching a
  scene's last panel records it too, so a crash after it loses nothing. A replay sends no operation:
  the economy refuses a repeat without storing it.
- **A failed write** (the first-session flag's disk write throwing) is reported and the viewer goes
  on: «كمّل» moves to the next scene or leaves, «تخطّى» and back leave, as M07's `ScenePage` reports
  its own. The scene then comes back as waiting. While a record is on its way, a second «كمّل» does
  nothing, or it would step past the sequence's end (T145).
- **Turns:** M22's talking turns run on the panel's Rive file, as M07's player does.
- **Motion:**
  - the panel slides in from the reading side with a fade (`sheetIn`);
  - bubbles pop (`bubblePop`), staggered 150 ms;
  - the current dot widens 10 → 26.
  - Under reduced motion: a crossfade ≤ 150 ms, the still drawing and no pop (M22's rule).
- **Accessibility:**
  - the panel is one button «اللوحة الجاية»;
  - each bubble reads as speaker and text, in authored order;
  - «اللوحة {i} من {n}» is announced politely on every advance.
- **Offline:** everything ships in the app (art, Rive and the pack), so the viewer never needs the
  network, and HANDOFF's not-downloaded state doesn't arise.

### Share (`ScenePanelShare`)

- `renderSharePicture` moves from `features/result/presentation/share_action.dart` to
  `lib/core/platform/offscreen_render.dart` as:

  ```dart
  Future<Uint8List> renderOffscreenPng(BuildContext context, Widget child, Size logicalSize, {double pixelRatio = 3});
  ```

  M08's `ShareCard` path calls it with its card. Its tests move with it, and its output is unchanged
  (M08's share golden).
- «شارك» renders `ScenePanelShare`: the current panel's **still** drawing (never Rive), its bubbles and
  a small wordmark strip, at 358×540 ×3. It then calls `ShareGateway.shareImage` with M08's share
  text pattern (`shareSceneText`, ARB).
- The picture carries nothing of the player's: the driver's bubble reads the default «الأسطى»
  (`shareSpeakerName`), never the name the player typed, which only the viewer shows (T145).
- A failure shows M08's share error toast. It works offline.

## The timeline (`/apartment/chapters`, `ChaptersPage`, research R13)

```dart
sealed class ChapterRow { }
final class DoneRow extends ChapterRow    { final int number; final String name; final PanelArtRef? thumb; final bool hasScenes; }
final class CurrentRow extends ChapterRow { final int number; final String name; final CurrentGoal goal; }
final class LockedRow extends ChapterRow  { final int number; final String name; }

List<ChapterRow> chapterRows(ContentSource c, PlayerProgress p, …);  // seven, by the glossary's ChapterId order
```

| Row | Rule |
| --- | --- |
| Done | the chapter is complete. Its thumbnail is the first panel of its last unlocked scene in story order. «شوف المشهد» → `/story/:chapterId`, absent without an unlocked scene |
| Current | the current chapter, unless the story has ended. A room goal: chip «{owned} من {total} قطع», description «{items} · المشهد: {goal scene title}» (the scene part dropped without one). Any other goal: chip «{saved} / {target} ج» or «{done} / {total} مشوار», description the goal's title (M08's `ChapterGoalTarget`) |
| Locked | every other chapter. A chapter the pack lacks takes ARB `chapterTeaserName(id)` |

- The header pill «ألبوم المشاهد» → `/story/album`.
- The rail fills to the current node's centre, or fully at the end of the story. It animates
  (`sheetIn`) on the first entry after the current chapter changes, kept in memory.
- Each row reads as one sentence: «الفصل {n}، {name}، خلص» / «…، دلوقتي، {goal}» / «…، مقفول».
- The list scrolls.

## The album (`/story/album`, `AlbumPage`, research R13, Q3)

```dart
sealed class AlbumCard { }
final class UnlockedCard extends AlbumCard { final int chapterNumber; final Scene scene; final PanelArtRef firstPanel; }
final class LockedCard extends AlbumCard   { final int chapterNumber; final String title; }

(List<AlbumCard>, int unlocked, int total) album(ContentSource c, PlayerProgress p, …);  // every scene of the pack, story order
```

- **Count chip:** «{unlocked} من {total}», counting the pack's scenes (seen or waiting count as
  unlocked).
- **Unlocked card:** the first panel's still drawing (h96), «الفصل {n}», the title (two lines), and
  «اتفرج تاني» → `/story/scene/:sceneId?then=/story/album`. Label «الفصل {n}: {title}، اتفرج تاني».
- **Locked card:** the locked look (`locked.bg`, the `outline` ring, a grey thumbnail with a lock),
  the chapter and title in `ink.2`, and «بيتفتح لما الفصل يخلص». It is inert. Label «الفصل {n}:
  {title}، لسه مقفول».
- **Grid:** two columns, gap 12, RTL; the page scrolls.

A locked scene's title shows: the album teases the story, as the design draws it.

## Tests

- **Domain:** `scene_sequence_test` (one scene, a chapter's sequence, nothing unlocked), `album_test`
  (order, count, a waiting scene counted unlocked), `chapter_rows_test` (seven rows, ARB names for
  absent chapters, each current-goal kind, the end).
- **Widget:**
  - `scene_viewer_page_test`: tap-to-complete then advance; the last panel's buttons; skip and back
    record; a sequence moves to the next scene and restarts the dots; a replay sends no op; the
    driver's name; reduced motion; the announcement.
  - `scene_share_test`: the fake gateway receives a PNG of the expected size; offline works.
  - `chapters_page_test` and `album_page_test`.
  - `offscreen_render_test`: moved from result, unchanged output.
- **Design:** samples, goldens and layout tests for `SceneViewer`, `Chapters` and `Album`, with
  `Album`'s card count from the sample pack's scenes (expected difference, research R18).
