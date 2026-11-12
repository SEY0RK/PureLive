#!/usr/bin/env python3
"""The 5.6.5 layout fixes, applied in place to a checkout.

Every anchor must match exactly once; the script stops otherwise. Re-running
is a no-op: each edit carries a marker that is checked first, so a branch that
already carries the change can be pushed again.
"""

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

LAYOUT = "apps/pure_live/lib/features/live_play/logic/room_layout.dart"
PAGE = "apps/pure_live/lib/features/live_play/live_play_page.dart"
GRADLE = "apps/pure_live/android/app/build.gradle.kts"


def fail(message):
    print(f"patch_565_layout: {message}", file=sys.stderr)
    raise SystemExit(1)


def patch(rel, old, new, marker):
    path = ROOT / rel
    if not path.is_file():
        fail(f"{rel}: missing")
    text = path.read_text(encoding="utf-8")
    if marker in text:
        print(f"skip  {rel}  {marker[:56]!r}")
        return
    count = text.count(old)
    if count != 1:
        fail(f"{rel}: anchor matched {count} times, expected 1:\n---\n{old}\n---")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")
    print(f"patch {rel}  {marker[:56]!r}")


# ---------------------------------------------------------------- room_layout

patch(
    LAYOUT,
    "import 'dart:math' as math;\n\nimport 'package:live_ui/live_ui.dart' show AppMotion, windowCompactHeight;",
    "import 'dart:math' as math;\n"
    "import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType, Size;\n"
    "\n"
    "import 'package:live_ui/live_ui.dart' show AppMotion, windowCompactHeight;",
    "import 'dart:ui' show DisplayFeature",
)

patch(
    LAYOUT,
    """RoomPageLayout roomPageLayout({
  required double width,
  required double height,
  required bool portraitPanel,
  bool mobile = true,
}) {
  if (height < roomCompactMaxHeight && width > height && width >= 600) {
    return mobile ? RoomPageLayout.landscape : RoomPageLayout.wide;
  }
  if (width >= roomWideMinWidth) return RoomPageLayout.wide;
  return portraitPanel ? RoomPageLayout.portraitPanel : RoomPageLayout.phone;
}""",
    """RoomPageLayout roomPageLayout({
  required double width,
  required double height,
  required bool portraitPanel,
  bool mobile = true,
  bool unfoldedFoldable = false,
  bool portraitStream = false,
}) {
  if (height < roomCompactMaxHeight && width > height && width >= 600) {
    return mobile ? RoomPageLayout.landscape : RoomPageLayout.wide;
  }
  if (width >= roomWideMinWidth) return RoomPageLayout.wide;
  // A07.5 c9: an unfolded foldable's inner screen is 600-839 wide, below the
  // 840 rule. Held sideways the window is wide and shallow, so the chat
  // column keeps its full height for either source and the stacked chat is
  // left a few dozen pixels (A07.5 c9b). Upright, only a portrait stream uses
  // that height; a 16:9 stream keeps the stack, where its picture is larger.
  if (unfoldedFoldable && width >= roomFoldableSplitMinWidth && (width > height || portraitStream)) {
    return RoomPageLayout.wide;
  }
  return portraitPanel ? RoomPageLayout.portraitPanel : RoomPageLayout.phone;
}""",
    "bool unfoldedFoldable = false,",
)

patch(
    LAYOUT,
    "/// The width of the wide room's chat column (3.x: 34 % of the window, 300 to\n"
    "/// 400; U.2d choice H3).\n"
    "double chatColumnWidth(double width) => (width * 0.34).clamp(300.0, 400.0);",
    """/// The width of the wide room's chat column (3.x: 34 % of the window, 300 to
/// 400; U.2d choice H3).
double chatColumnWidth(double width) => (width * 0.34).clamp(300.0, 400.0);

/// The share of the page the stacked picture may take: 5.x clamped its 16:9
/// box to 60 % of the height, and the source-shaped box keeps that ceiling.
const double phonePictureShare = 0.6;

/// The least width that lets an unfolded foldable split (A07.5 c9): a
/// book-style foldable's inner screen is 600-839 wide, below
/// [roomWideMinWidth]; an ordinary window keeps the 840 rule.
const double roomFoldableSplitMinWidth = 600;

/// The height of the picture box above the chat ([RoomPageLayout.phone]): the
/// source's own shape at the full width, at most [share] of [height].
///
/// 3.x `resolveCompatibilityVideoHeight`: a fixed 16:9 box left a 9:16 source
/// a strip in the middle with black bands above and below (Issue #927). A
/// landscape source still gets its plain 16:9 box, and an unknown
/// [aspectRatio] falls back to it, so nothing moves before the first frame.
double phonePictureHeight({
  required double width,
  required double height,
  double? aspectRatio,
  double share = phonePictureShare,
}) {
  if (!width.isFinite || width <= 0) return 0;
  final ratio = aspectRatio != null && aspectRatio.isFinite && aspectRatio > 0 ? aspectRatio : 16 / 9;
  final natural = width / ratio;
  if (!height.isFinite) return natural;
  if (height <= 0) return 0;
  return natural.clamp(0.0, height * share.clamp(0.0, 1.0));
}

/// Whether [features] report an unfolded foldable: a fold or a hinge that is
/// flat (fully open) or half open. A cut-out never counts.
///
/// [DisplayHinge.find] cannot answer this: a flat fold's bounds have no
/// width, and it skips those.
bool unfoldedFoldable(Iterable<DisplayFeature> features) {
  for (final feature in features) {
    if (feature.type == DisplayFeatureType.cutout) continue;
    if (feature.state == DisplayFeatureState.postureFlat ||
        feature.state == DisplayFeatureState.postureHalfOpened) {
      return true;
    }
  }
  return false;
}

/// Whether the window is a foldable's open inner screen (A07.5 c9): the system
/// reports a fold or a hinge, or, on a phone or tablet, the window is nearly
/// square — 600-839 wide and at most 1.25 times as tall. No ordinary phone or
/// tablet in portrait is (720 x 1000 is 1.39, 800 x 1280 is 1.6), while a
/// book-style foldable's inner screen is (673 x 841 is 1.25). The fallback
/// covers a device that reports no display feature at all.
bool foldableWindow({
  required Size size,
  required Iterable<DisplayFeature> features,
  required bool mobile,
}) {
  if (unfoldedFoldable(features)) return true;
  if (!mobile || !size.width.isFinite || !size.height.isFinite) return false;
  if (size.width < roomFoldableSplitMinWidth || size.width >= roomWideMinWidth) return false;
  if (size.height < size.width) return false;
  return size.height / size.width <= 1.25;
}""",
    "double phonePictureHeight(",
)

# --------------------------------------------------------------- live_play_page

patch(
    PAGE,
    """  /// What the player found, or before the first frame what the platform
  /// declared: a portrait picture.
  final ValueNotifier<bool> _detectedPortrait = ValueNotifier(false);""",
    """  /// What the player found, or before the first frame what the platform
  /// declared: a portrait picture.
  final ValueNotifier<bool> _detectedPortrait = ValueNotifier(false);

  /// The picture's shape (width over height): the decoder's, or before the
  /// first frame what the platform declared for the line (F.1b). The stacked
  /// picture keeps the source's shape (A07.2); null until either is known.
  final ValueNotifier<double?> _detectedAspect = ValueNotifier(null);

  /// The stacked picture follows the source's shape instead of a fixed 16:9
  /// box ("兼容 16:9" on a 9:16 stream, Issue #927). Off returns to 5.6.5.
  static const bool phonePictureFollowsSource = true;

  /// An unfolded foldable splits from [roomFoldableSplitMinWidth] for a
  /// portrait stream (A07.5 c9). Off returns to 5.6.5's 840 only.
  static const bool foldableSplitsFrom600 = true;""",
    "final ValueNotifier<double?> _detectedAspect",
)

patch(
    PAGE,
    """    _detectedPortrait.value = session.state.expectsPortrait;
    _shape = session.states.listen((state) {
      if (state.expectsPortrait != _detectedPortrait.value) _detectedPortrait.value = state.expectsPortrait;
    });""",
    """    _detectedPortrait.value = session.state.expectsPortrait;
    _detectedAspect.value = session.state.expectedAspectRatio;
    _shape = session.states.listen((state) {
      if (state.expectsPortrait != _detectedPortrait.value) _detectedPortrait.value = state.expectsPortrait;
      // A replay reports its position every tick while its shape changes
      // once (the declared ratio giving way to the decoded one): only a
      // changed shape rebuilds the page.
      final aspect = state.expectedAspectRatio;
      if (aspect != _detectedAspect.value) _detectedAspect.value = aspect;
    });""",
    "_detectedAspect.value = session.state.expectedAspectRatio;",
)

patch(
    PAGE,
    "                listenable: Listenable.merge([_orientation, _detectedPortrait]),",
    "                listenable: Listenable.merge([_orientation, _detectedPortrait, _detectedAspect]),",
    "Listenable.merge([_orientation, _detectedPortrait, _detectedAspect])",
)

patch(
    PAGE,
    """    _detectedPortrait.dispose();
    _guideReveal.dispose();""",
    """    _detectedPortrait.dispose();
    _detectedAspect.dispose();
    _guideReveal.dispose();""",
    "_detectedAspect.dispose();",
)

patch(
    PAGE,
    """      final portrait = _portraitStream(settings);
      // Above the Scaffold, whose body no longer sees it (A07.18).
      final keyboard = MediaQuery.viewInsetsOf(context).bottom;
      final layout = roomPageLayout(
        width: page.maxWidth,
        height: page.maxHeight,
        mobile: _platform.mobile,
        portraitPanel: portraitPanelEligible(""",
    """      final portrait = _portraitStream(settings);
      // Above the Scaffold, whose body no longer sees it (A07.18).
      final keyboard = MediaQuery.viewInsetsOf(context).bottom;
      final layout = roomPageLayout(
        width: page.maxWidth,
        height: page.maxHeight,
        mobile: _platform.mobile,
        unfoldedFoldable:
            foldableSplitsFrom600 &&
            foldableWindow(
              size: Size(page.maxWidth, page.maxHeight),
              features: MediaQuery.displayFeaturesOf(context),
              mobile: _platform.mobile,
            ),
        portraitStream: portrait,
        portraitPanel: portraitPanelEligible(""",
    "foldableSplitsFrom600 &&",
)

patch(
    PAGE,
    """  Widget _phone(
    LiveRoomController controller,
    _LayoutSettings settings,
    BoxConstraints constraints, {
    double keyboard = 0,
  }) {
    final height = (constraints.maxWidth * 9 / 16).clamp(0.0, constraints.maxHeight * 0.6);""",
    """  Widget _phone(
    LiveRoomController controller,
    _LayoutSettings settings,
    BoxConstraints constraints, {
    double keyboard = 0,
  }) {
    // The picture keeps the source's shape (A07.2): a 9:16 stream no longer
    // sits in a 16:9 box with black bands (Issue #927). A 16:9 stream keeps
    // exactly 5.6.5's height.
    final height = phonePictureHeight(
      width: constraints.maxWidth,
      height: constraints.maxHeight,
      aspectRatio: phonePictureFollowsSource ? _detectedAspect.value : null,
    );""",
    "final height = phonePictureHeight(",
)

# --------------------------------------------------------------------- gradle

patch(
    GRADLE,
    '        applicationId = "com.mystyle.purelive"',
    """        // The candidate build lives next to the release: it is signed with
        // another key, so it can never update it (PURELIVE_CANDIDATE=true).
        applicationId =
            if (System.getenv("PURELIVE_CANDIDATE") == "true") {
                "com.mystyle.purelive.candidate"
            } else {
                "com.mystyle.purelive"
            }""",
    "com.mystyle.purelive.candidate",
)

patch(
    GRADLE,
    '        manifestPlaceholders["appLabel"] = "纯粹直播"',
    '        manifestPlaceholders["appLabel"] =\n'
    '            if (System.getenv("PURELIVE_CANDIDATE") == "true") "纯粹直播 测试" else "纯粹直播"',
    'System.getenv("PURELIVE_CANDIDATE") == "true") "纯粹直播 测试"',
)

# ------------------------------------------------- A07.5 c9c: tabletop posture

patch(
    LAYOUT,
    "import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType, Size;",
    "import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType, Rect, Size;",
    "Rect, Size;",
)

patch(
    LAYOUT,
    """  if (size.height < size.width) return false;
  return size.height / size.width <= 1.25;
}""",
    """  if (size.height < size.width) return false;
  return size.height / size.width <= 1.25;
}

/// The horizontal hinge of a half-opened foldable (book or tabletop
/// posture, A07.5 c9c): its bounds are the band between the upper and the
/// lower half of the window. A horizontal fold is wider than it is tall; a
/// vertical one splits left and right instead, and a cut-out never counts.
Rect? tabletopFold(Iterable<DisplayFeature> features) {
  for (final feature in features) {
    if (feature.type == DisplayFeatureType.cutout) continue;
    if (feature.state != DisplayFeatureState.postureHalfOpened) continue;
    if (feature.bounds.width >= feature.bounds.height) return feature.bounds;
  }
  return null;
}""",
    "Rect? tabletopFold(",
)

TABLETOP_WIDGET = """  /// Fullscreen, held sideways, halfway folded (A07.5 c9c): the hinge splits
  /// the screen itself, so the picture takes the upper pane and the chat list
  /// the lower one, and the hinge band stays black. Only a fullscreen room
  /// gets here; the page keeps its own layouts. The quality and line move
  /// into the picture's bars, as in the landscape fullscreen, so the chat
  /// keeps every line it can. Panels stay under the picture.
  Widget _tabletopFullscreen(
    LiveRoomController controller,
    _LayoutSettings settings,
    BoxConstraints constraints, {
    required Rect fold,
    double keyboard = 0,
  }) {
    final scheme = Theme.of(context).colorScheme;
    // Feature bounds are in window coordinates; scale their position onto
    // the body's height (which excludes the app bar) instead of subtracting
    // an inset that differs between Android releases.
    final window = MediaQuery.sizeOf(context).height;
    final share = window > 0 ? (fold.center.dy / window).clamp(0.35, 0.65) : 0.5;
    final top = (constraints.maxHeight * share).clamp(0.0, constraints.maxHeight * 0.8);
    final gap = fold.height.clamp(0.0, 32.0);
    final player = _player(
      controller,
      settings,
      arrangement: ControlsArrangement.landscape,
      onTitle: _toggleDetails,
      pickersInBar: true,
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        Column(
          key: const ValueKey('live-play-tabletop-split'),
          children: [
            SizedBox(
              key: const ValueKey('live-play-tabletop-picture'),
              height: top,
              child: ColoredBox(color: OnVideoColors.ground, child: player),
            ),
            SizedBox(height: gap, child: const ColoredBox(color: OnVideoColors.ground)),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: scheme.outlineVariant)),
                ),
                child: _withDetails(
                  controller,
                  ListenableSelector<bool>(
                    listenable: controller,
                    selector: () => controller.isArchive,
                    builder: (context, archive, _) => archive
                        ? RoomReplayLibrary(controller: controller)
                        : ChatList(controller: controller, memory: _memory),
                  ),
                ),
              ),
            ),
          ],
        ),
        _panelUnderPicture(
          controller,
          top: top + gap,
          keyboard: keyboard,
          key: const ValueKey('live-play-tabletop-panel'),
        ),
      ],
    );
  }

"""

patch(
    PAGE,
    "  /// A07.17 c2 (choice A): a phone held sideways, not in fullscreen. The",
    TABLETOP_WIDGET + "  /// A07.17 c2 (choice A): a phone held sideways, not in fullscreen. The",
    "Widget _tabletopFullscreen(",
)

patch(
    PAGE,
    """            final portrait = _portraitStream(settings);
            final upright = arrangement == ControlsArrangement.portraitFullscreen;""",
    """            final portrait = _portraitStream(settings);
            // A07.5 c9c: fullscreen, held sideways, halfway folded — the
            // hinge divides the screen itself, so the picture goes above it
            // and the chat below. Every other fullscreen keeps its layout.
            final fold = _platform.mobile && _display == RoomDisplay.fullscreen && !portrait
                ? tabletopFold(MediaQuery.displayFeaturesOf(context))
                : null;
            if (fold != null && arrangement == ControlsArrangement.landscape) {
              return _tabletopFullscreen(controller, settings, constraints, fold: fold, keyboard: keyboard);
            }
            final upright = arrangement == ControlsArrangement.portraitFullscreen;""",
    "return _tabletopFullscreen(",
)


print("patch_565_layout: done")
