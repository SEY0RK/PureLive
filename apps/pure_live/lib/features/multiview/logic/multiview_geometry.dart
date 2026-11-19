import 'dart:math' as math;
import 'dart:ui';

import 'package:pure_live/features/multiview/logic/multiview_controller.dart';

/// The most cells this device decodes at once (UI_PLAN §9.3: the multi-view's
/// cells follow what the device can do). Phones keep four, the size of
/// every layout (3.x); desktops get 3.x's nine with eight processors or
/// more, six with six or seven, and four below that.
int multiviewMaxCells({required bool mobile, required int processors}) {
  if (mobile) return MultiviewLayout.focus.capacity;
  if (processors >= 8) return MultiviewController.desktopMaxCells;
  if (processors >= 6) return 6;
  return MultiviewLayout.focus.capacity;
}

/// The items of a scrolling rail with some part in sight (3.x
/// `visibleFocusRailCells`): [count] items of [extent] each, scrolled by
/// [offset] in a viewport [viewport] long. Returns the first and the end
/// (exclusive) index.
(int, int) visibleRailRange({
  required int count,
  required double offset,
  required double viewport,
  required double extent,
}) {
  if (count <= 0 || !offset.isFinite || !viewport.isFinite || !extent.isFinite || viewport <= 0 || extent <= 0) {
    return (0, 0);
  }
  final start = math.max<double>(0, offset);
  final first = (start / extent).floor().clamp(0, count);
  final end = ((start + viewport) / extent).ceil().clamp(first, count);
  return (first, end);
}

/// Cells are 16:9 (docs/A-界面设计/A13-网络电视和多画面界面/A13.2-多画面 c2).
const double cellAspect = 16 / 9;

/// One cell of a four-picture template, in the design's 1920 × 1080 space.
final class _Slot {
  const _Slot(this.left, this.top, this.width, this.height, {this.portrait = false, this.large = false});

  final double left;
  final double top;
  final double width;
  final double height;

  /// The slot takes a picture taller than wide.
  final bool portrait;

  /// The 1+3 layout's large slot: it takes the focused cell.
  final bool large;
}

/// The four-picture templates (docs: A13.2-多画面): the large cell keeps the
/// shape its picture wants and the three small ones split the rest by their
/// own shapes. Coordinates are the design's 1920 × 1080; null when the
/// composition has no template — a lone landscape among three portraits
/// would squeeze the portraits into 640 × 360 slivers, so it keeps the
/// scrolling rail instead.
List<_Slot>? _slotsFor(int portraits, bool largePortrait) => switch ((portraits, largePortrait)) {
  // 4 landscape: the large one left, three 16:9 below each other on the right.
  (0, _) => const [
    _Slot(0, 0, 1280, 1080, large: true),
    _Slot(1280, 0, 640, 360),
    _Slot(1280, 360, 640, 360),
    _Slot(1280, 720, 640, 360),
  ],
  // 4 portrait: the large one left, three columns on the right.
  (4, _) => const [
    _Slot(0, 0, 607.5, 1080, portrait: true, large: true),
    _Slot(607.5, 0, 437.5, 1080, portrait: true),
    _Slot(1045, 0, 437.5, 1080, portrait: true),
    _Slot(1482.5, 0, 437.5, 1080, portrait: true),
  ],
  // 3 landscape + 1 portrait, the landscape large: the portrait's own column.
  (1, false) => const [
    _Slot(0, 0, 1280, 720, large: true),
    _Slot(1280, 0, 640, 1080, portrait: true),
    _Slot(0, 720, 640, 360),
    _Slot(640, 720, 640, 360),
  ],
  // 3 landscape + 1 portrait, the portrait focused: the mirror of the
  // landscape-large template. The portrait keeps its full-height column on
  // the LEFT (the main side in every template), the three landscapes take the
  // right: one above, two below. Same 98.3 % of picture as (1, false).
  (1, true) => const [
    _Slot(0, 0, 640, 1080, portrait: true, large: true),
    _Slot(640, 0, 1280, 720),
    _Slot(640, 720, 640, 360),
    _Slot(1280, 720, 640, 360),
  ],
  // 2 + 2, the portrait large: two portrait columns, the landscapes right.
  (2, true) => const [
    _Slot(0, 0, 607.5, 1080, portrait: true, large: true),
    _Slot(607.5, 0, 437.5, 1080, portrait: true),
    _Slot(1045, 0, 875, 540),
    _Slot(1045, 540, 875, 540),
  ],
  // 2 + 2, the landscape large: portraits stacked on the right.
  (2, false) => const [
    _Slot(0, 0, 1280, 720, large: true),
    _Slot(1280, 0, 640, 540, portrait: true),
    _Slot(1280, 540, 640, 540, portrait: true),
    _Slot(0, 720, 1280, 360),
  ],
  // 1 landscape + 3 portraits, the portrait large.
  (3, true) => const [
    _Slot(0, 0, 607.5, 1080, portrait: true, large: true),
    _Slot(607.5, 0, 656.25, 720, portrait: true),
    _Slot(1263.75, 0, 656.25, 720, portrait: true),
    _Slot(607.5, 720, 1312.5, 360),
  ],
  // 1 landscape + 3 portraits with the landscape large: no template, the
  // portraits would be 640 × 360 slivers (A13.2 c2, the rail shows them).
  (3, false) => null,
  _ => null,
};

/// Splits a strip into pieces, along its width ([vertical] false) or height.
/// [weights] are the preferred extents; the gaps are taken out first.
List<Rect> _splitStrip(Rect strip, List<double> weights, {required bool vertical, required double gap}) {
  final total = weights.fold<double>(0, (a, b) => a + b);
  if (total <= 0 || weights.isEmpty) return [strip];
  final extent = vertical ? strip.height : strip.width;
  final usable = extent - gap * (weights.length - 1);
  if (usable <= 0) return [strip];
  final out = <Rect>[];
  var at = vertical ? strip.top : strip.left;
  for (final weight in weights) {
    final length = usable * weight / total;
    out.add(vertical
        ? Rect.fromLTWH(strip.left, at, strip.width, length)
        : Rect.fromLTWH(at, strip.top, length, strip.height));
    at += length + gap;
  }
  return out;
}

/// How much picture the cells actually show in [rects], given the shapes the
/// streams want. Used only to choose between candidates, never to crop.
double _visibleArea(List<Rect> rects, List<double> aspects) {
  var total = 0.0;
  for (var i = 0; i < rects.length; i++) {
    final shape = rects[i].width / rects[i].height;
    if (!shape.isFinite || shape <= 0) return -1;
    total += rects[i].width * rects[i].height * math.min(aspects[i] / shape, shape / aspects[i]);
  }
  return total;
}

/// A foldable's unfolded inner screen is close to 1.1:1 (squarish), not 16:9.
/// Compose the four cells from the canvas itself: the large one keeps the
/// shape of its stream, the other three take the rest in a strip or a grid.
/// Null when no candidate can keep the large cell clearly larger.
List<Rect>? _squarishCells({
  required Size inner,
  required List<double> aspects,
  required int focused,
  required double gap,
}) {
  if (inner.width <= 0 || inner.height <= 0) return null;
  final others = [for (var i = 0; i < 4; i++) if (i != focused) i];
  final mainAspect = aspects[focused];
  final candidates = <List<Rect>>[];

  // Large picture across the top, three below it.
  final topHeight = (inner.width / mainAspect).clamp(inner.height * 0.3, inner.height * 0.72);
  final top = Rect.fromLTWH(0, 0, inner.width, topHeight);
  final below = Rect.fromLTWH(0, topHeight + gap, inner.width, inner.height - topHeight - gap);
  if (below.height > 0) {
    final belowRects = _splitStrip(below, [for (final i in others) aspects[i]], vertical: false, gap: gap);
    if (belowRects.length == others.length) {
      final cells = List<Rect?>.filled(4, null);
      cells[focused] = top;
      for (var k = 0; k < others.length; k++) {
        cells[others[k]] = belowRects[k];
      }
      if (!cells.contains(null)) candidates.add([for (final rect in cells) rect!]);
    }
  }

  // Large picture down the left side, three beside it.
  final leftWidth = (inner.height * mainAspect).clamp(inner.width * 0.3, inner.width * 0.72);
  final left = Rect.fromLTWH(0, 0, leftWidth, inner.height);
  final beside = Rect.fromLTWH(leftWidth + gap, 0, inner.width - leftWidth - gap, inner.height);
  if (beside.width > 0) {
    final besideRects = _splitStrip(beside, [for (final i in others) 1 / aspects[i]], vertical: true, gap: gap);
    if (besideRects.length == others.length) {
      final cells = List<Rect?>.filled(4, null);
      cells[focused] = left;
      for (var k = 0; k < others.length; k++) {
        cells[others[k]] = besideRects[k];
      }
      if (!cells.contains(null)) candidates.add([for (final rect in cells) rect!]);
    }
  }

  // A full-height column for the large picture, the three others in a
  // 2 × 2 grid with the spare cell empty (the best fit for three portraits).
  final columnWidth = (inner.height * mainAspect).clamp(inner.width * 0.3, inner.width * 0.72);
  final column = Rect.fromLTWH(0, 0, columnWidth, inner.height);
  final rest = Rect.fromLTWH(columnWidth + gap, 0, inner.width - columnWidth - gap, inner.height);
  if (rest.width > 0 && others.length == 3) {
    const grid = [0, 1, 2, 3];
    final cells = List<Rect?>.filled(4, null);
    cells[focused] = column;
    for (var k = 0; k < 3; k++) {
      final slot = grid[k];
      cells[others[k]] = Rect.fromLTWH(
        rest.left + (slot % 2) * (rest.width + gap) / 2,
        rest.top + (slot ~/ 2) * (rest.height + gap) / 2,
        (rest.width - gap) / 2,
        (rest.height - gap) / 2,
      );
    }
    if (!cells.contains(null)) candidates.add([for (final rect in cells) rect!]);
  }

  List<Rect>? best;
  var bestArea = -1.0;
  for (final cells in candidates) {
    final large = cells[focused].width * cells[focused].height;
    var largestOther = 0.0;
    for (final i in others) {
      largestOther = math.max(largestOther, cells[i].width * cells[i].height);
    }
    if (large < largestOther * 1.15) continue;
    final area = _visibleArea(cells, aspects);
    if (area > bestArea) {
      bestArea = area;
      best = cells;
    }
  }
  return best;
}

/// The two cells of a 1×2 layout. The halves are always equal: a native
/// split gives one stream its own shape but leaves the other a sliver, and
/// on a phone the unequal widths read as a broken layout. Pick the equal
/// split — columns or rows — that shows more picture on this canvas.
List<Rect>? _dualCells({
  required Size inner,
  required List<double> aspects,
  required double gap,
}) {
  if (aspects.length != 2 || inner.width <= 0 || inner.height <= 0) return null;
  for (final aspect in aspects) {
    if (!aspect.isFinite || aspect <= 0) return null;
  }
  final width = inner.width, height = inner.height;
  // Equal halves only. A "native" column for a 9:16 stream on a 16:9 window
  // left the other cell 68 % wide; on a phone it was 56 %/44 %. Neither reads
  // as a 1×2 layout. The wall's height (see WallGeometry.contentHeight) is
  // what adapts to portrait streams now, not the split ratio.
  final candidates = <List<Rect>>[
    [
      Rect.fromLTWH(0, 0, (width - gap) / 2, height),
      Rect.fromLTWH((width + gap) / 2, 0, (width - gap) / 2, height),
    ],
    [
      Rect.fromLTWH(0, 0, width, (height - gap) / 2),
      Rect.fromLTWH(0, (height + gap) / 2, width, (height - gap) / 2),
    ],
  ];

  List<Rect>? best;
  var bestArea = -1.0;
  for (final cells in candidates) {
    final area = _visibleArea(cells, aspects);
    if (area > bestArea) {
      bestArea = area;
      best = cells;
    }
  }
  return best;
}

/// The orders the three other streams can take the three strips of a
/// candidate. Cheap to enumerate, and it keeps the scorer honest about which
/// shape belongs in which strip.
const List<List<int>> _threeSlotOrders = [
  [0, 1, 2],
  [0, 2, 1],
  [1, 0, 2],
  [1, 2, 0],
  [2, 0, 1],
  [2, 1, 0],
];

/// A phone's immersive/fullscreen canvas is taller than it is wide (aspect
/// below 0.8). Stretching the 1920×1080 template onto it gives four narrow
/// strips — every picture lands in a 17–27 % letterbox, which reads as a
/// brute-force stretch. Compose 1+3 from the canvas itself instead: a full-
/// width row or a full-height column for the focused picture, the other
/// three in strips or a 2×2 remainder. Nothing is cropped; the composition
/// that shows most picture wins.
List<Rect>? _portraitCells({
  required Size inner,
  required List<double> aspects,
  required int focused,
  required double gap,
}) {
  if (inner.width <= 0 || inner.height <= 0) return null;
  final others = [for (var i = 0; i < 4; i++) if (i != focused) i];
  final w = inner.width, h = inner.height;
  final candidates = <List<Rect>>[];

  void collect(Rect main, Rect rest, {required bool restVertical}) {
    // Equal shares, shares proportional to the streams' shapes, and their
    // inverses: a portrait stream wants a narrow column, a landscape one a
    // short row. The scorer picks whichever fits this canvas.
    final weights = <List<double>>[
      [1.0, 1.0, 1.0],
      [for (final i in others) aspects[i].clamp(0.45, 2.2).toDouble()],
      [for (final i in others) (1 / aspects[i]).clamp(0.45, 2.2).toDouble()],
    ];
    for (final weight in weights) {
      final strips = _splitStrip(rest, weight, vertical: restVertical, gap: gap);
      if (strips.length != 3) continue;
      for (final order in _threeSlotOrders) {
        final cells = List<Rect?>.filled(4, null);
        cells[focused] = main;
        for (var k = 0; k < 3; k++) {
          cells[others[order[k]]] = strips[k];
        }
        if (!cells.contains(null)) candidates.add([for (final rect in cells) rect!]);
      }
    }
  }

  // Focused picture as a full-width row. Its own shape is one option, but on
  // a tall canvas the three others often need a taller strip than that
  // leaves, so a range of heights is tried (top and bottom variants both).
  for (final share in [0.28, 0.38, 0.48, 0.58, 0.68, 0.78]) {
    final rowHeight = share == 0.28
        ? (w / aspects[focused]).clamp(h * share, h * 0.82).toDouble()
        : h * share;
    if (h - rowHeight <= gap) continue;
    collect(
      Rect.fromLTWH(0, 0, w, rowHeight),
      Rect.fromLTWH(0, rowHeight + gap, w, h - rowHeight - gap),
      restVertical: false,
    );
    collect(
      Rect.fromLTWH(0, h - rowHeight, w, rowHeight),
      Rect.fromLTWH(0, 0, w, h - rowHeight - gap),
      restVertical: false,
    );
  }

  // Focused picture as a full-height column, on either side, at several
  // widths: the strip's shape changes which streams can use it.
  for (final share in [0.34, 0.42, 0.50, 0.58, 0.66]) {
    final columnWidth = w * share;
    if (w - columnWidth <= gap) continue;
    collect(
      Rect.fromLTWH(0, 0, columnWidth, h),
      Rect.fromLTWH(columnWidth + gap, 0, w - columnWidth - gap, h),
      restVertical: true,
    );
    collect(
      Rect.fromLTWH(w - columnWidth, 0, columnWidth, h),
      Rect.fromLTWH(0, 0, w - columnWidth - gap, h),
      restVertical: true,
    );
  }

  // Four rows, the focused one taking a taller share.
  for (final weight in [1.4, 1.8, 2.2]) {
    final rows = _splitStrip(Rect.fromLTWH(0, 0, w, h), [weight, 1, 1, 1], vertical: true, gap: gap);
    if (rows.length != 4) continue;
    final cells = List<Rect?>.filled(4, null);
    cells[focused] = rows[0];
    for (var k = 0; k < 3; k++) {
      cells[others[k]] = rows[k + 1];
    }
    candidates.add([for (final rect in cells) rect!]);
  }

  // A side column for the focused picture and a 2×2 remainder with one empty
  // slot — the best shape for three portraits.
  final sideWidth = (h * aspects[focused]).clamp(w * 0.34, w * 0.66).toDouble();
  final rest = Rect.fromLTWH(sideWidth + gap, 0, w - sideWidth - gap, h);
  if (rest.width > gap) {
    final halfW = (rest.width - gap) / 2;
    final halfH = (rest.height - gap) / 2;
    final grid = [
      Rect.fromLTWH(rest.left, rest.top, halfW, halfH),
      Rect.fromLTWH(rest.left + halfW + gap, rest.top, halfW, halfH),
      Rect.fromLTWH(rest.left, rest.top + halfH + gap, halfW, halfH),
    ];
    for (final order in _threeSlotOrders) {
      final cells = List<Rect?>.filled(4, null);
      cells[focused] = Rect.fromLTWH(0, 0, sideWidth, h);
      for (var k = 0; k < 3; k++) {
        cells[others[order[k]]] = grid[k];
      }
      if (!cells.contains(null)) candidates.add([for (final rect in cells) rect!]);
    }
  }

  double fit(Rect rect, double aspect) {
    final shape = rect.width / rect.height;
    return math.min(aspect / shape, shape / aspect);
  }

  // A raw area score alone put a 9:16 stream in a 92-pixel column and called
  // it a win: its letterbox was 28 % of the cell. Demand that every picture
  // gets at least 30 % of its own shape before comparing candidates. If no
  // composition can do that (e.g. two landscapes among three portraits),
  // fall back to the area winner — an extreme canvas has no fair answer.
  for (final floor in [0.30, 0.0]) {
    List<Rect>? best;
    var bestArea = -1.0;
    for (final cells in candidates) {
      var usable = true;
      for (var i = 0; i < 4; i++) {
        final rect = cells[i];
        if (rect.width < w * 0.12 || rect.height < h * 0.05 || fit(rect, aspects[i]) < floor) {
          usable = false;
          break;
        }
      }
      if (!usable) continue;
      final mainArea = cells[focused].width * cells[focused].height;
      var largestOther = 0.0;
      for (final i in others) {
        largestOther = math.max(largestOther, cells[i].width * cells[i].height);
      }
      // On a tall canvas a mixed set cannot give the main cell four times the
      // area of every other one; keep it clearly, not hugely, bigger.
      if (mainArea < largestOther * 1.05) continue;
      final area = _visibleArea(cells, aspects);
      if (area > bestArea) {
        bestArea = area;
        best = cells;
      }
    }
    if (best != null) return best;
  }
  return null;
}

/// The template's cells for [aspects], in cell order, the height the four
/// take at this width, and which cell got the large slot.
(List<Rect>, double, int)? _templateCells({
  required List<double> aspects,
  required int focused,
  required Size inner,
  required double gap,
}) {
  if (aspects.length != 4 || focused < 0 || focused >= 4) return null;
  if (inner.width <= 0 || inner.height <= 0) return null;
  var portraits = 0;
  for (final aspect in aspects) {
    if (!aspect.isFinite || aspect <= 0) return null;
    if (aspect < 1) portraits++;
  }

  // A foldable's inner screen, a tablet in square-ish proportions and a
  // rotated phone all need the canvas itself to decide where the cells go.
  // A phone's immersive screen is the opposite extreme: taller than wide,
  // and the design template would only stretch every slot into a sliver.
  final canvasAspect = inner.width / inner.height;
  if (canvasAspect < 0.8) {
    final portrait = _portraitCells(inner: inner, aspects: aspects, focused: focused, gap: gap);
    if (portrait != null) return (portrait, inner.height, focused);
  }
  if (canvasAspect >= 0.8 && canvasAspect <= 1.5) {
    final squarish = _squarishCells(inner: inner, aspects: aspects, focused: focused, gap: gap);
    if (squarish != null) return (squarish, inner.height, focused);
  }

  var chosen = _slotsFor(portraits, aspects[focused] < 1);
  // On a 16:9 canvas, one portrait + three landscapes has two mirrored
  // templates: the focused stream's shape picks which side its column is on.
  // Which of the three landscapes is focused is not forced — any of them can
  // take the large slot, so tapping 1, 2 or 3 always moves that picture.
  if (canvasAspect > 1.5 && portraits == 1) {
    chosen = _slotsFor(1, aspects[focused] < 1);
  }
  if (chosen == null) return null;

  // The focused cell takes the large slot — whichever of the four it is.
  var largeIndex = focused;
  // The design's 1920 × 1080 coordinates are fractions: map them onto the
  // actual canvas instead of fitting a 16:9 letterbox inside it.
  // The cell with the large slot is [largeIndex] (the focused one); the
  // others fill by shape, in order.
  final queue = {true: <int>[], false: <int>[]};
  for (var i = 0; i < 4; i++) {
    if (i != largeIndex) queue[aspects[i] < 1]!.add(i);
  }
  final placed = List<Rect?>.filled(4, null);
  for (final slot in chosen) {
    final int index;
    if (slot.large) {
      index = largeIndex;
    } else {
      final waiting = queue[slot.portrait]!;
      if (waiting.isEmpty) return null;
      index = waiting.removeAt(0);
    }
    if (placed[index] != null) return null;
    final rect = Rect.fromLTWH(
      slot.left / 1920 * inner.width,
      slot.top / 1080 * inner.height,
      slot.width / 1920 * inner.width,
      slot.height / 1080 * inner.height,
    ).deflate(gap / 2);
    if (rect.width <= 0 || rect.height <= 0) return null;
    placed[index] = rect;
  }
  if (placed.contains(null)) return null;
  return ([for (final rect in placed) rect!], inner.height, largeIndex);
}


/// Where the cells of a layout go (docs/A-界面设计/A13-网络电视和多画面界面/A13.2-多画面): 16:9 cells as large
/// as the area lets them be, centred; 1×2 one above the other or side by
/// side, and 1+3 with its small cells below or beside the large one,
/// whichever shows larger pictures.
final class WallGeometry {
  /// Creates the geometry.
  const new({required this.size, required this.cells, this.rail, this.railVertical = false, this.railExtent = 0, this.largeCell = 0});

  /// The cells of [layout] in `width` × `height` (an infinite height: as
  /// tall as the width wants); `gap` between cells and `padding` around them.
  factory of(
    MultiviewLayout layout, {
    required double width,
    double height = double.infinity,
    double gap = 3,
    double padding = 3,
    List<double>? aspects,
    int focused = 0,
  }) {
    if (layout == MultiviewLayout.dual && aspects != null && aspects.length == 2) {
      final across = math.max<double>(0, width - padding * 2);
      final inner = Size(
        across,
        height.isFinite ? math.max<double>(0, height - padding * 2) : across * 9 / 16,
      );
      final dual = _dualCells(inner: inner, aspects: aspects, gap: gap);
      if (dual != null) {
        return WallGeometry(
          size: Size(width, height.isFinite ? height : inner.height + padding * 2),
          cells: [for (final rect in dual) rect.shift(Offset(padding, padding))],
        );
      }
    }

    if (layout == MultiviewLayout.focus) {
      if (aspects != null && aspects.length == 4) {
        final across = math.max<double>(0, width - padding * 2);
        final inner = Size(
          across,
          height.isFinite ? math.max<double>(0, height - padding * 2) : across * 1080 / 1920,
        );
        final template = _templateCells(aspects: aspects, focused: focused, inner: inner, gap: gap);
        if (template != null) {
          final (cells, contentHeight, largeCell) = template;
          return WallGeometry(
            size: Size(width, height.isFinite ? height : contentHeight + padding * 2),
            cells: [for (final rect in cells) rect.shift(Offset(padding, padding))],
            largeCell: largeCell,
          );
        }
      }
      return WallGeometry.focus(width: width, height: height, gap: gap, padding: padding);
    }
    final shapes = switch (layout) {
      MultiviewLayout.single => const [(1, 1)],
      MultiviewLayout.dual => const [(1, 2), (2, 1)],
      MultiviewLayout.vertical => const [(1, 4)],
      _ => const [(2, 2)],
    };
    (double, int, int)? best;
    for (final (columns, rows) in shapes) {
      final byWidth = (width - padding * 2 - gap * (columns - 1)) / columns;
      final byHeight = (height - padding * 2 - gap * (rows - 1)) / rows * cellAspect;
      final cellWidth = math.max<double>(0, math.min(byWidth, byHeight));
      if (best == null || cellWidth > best.$1 + 0.5) best = (cellWidth, columns, rows);
    }
    final (cellWidth, columns, rows) = best!;
    final cellHeight = cellWidth / cellAspect;
    final content = Size(
      cellWidth * columns + gap * (columns - 1) + padding * 2,
      cellHeight * rows + gap * (rows - 1) + padding * 2,
    );
    final size = Size(width, height.isFinite ? height : content.height);
    final origin = Offset((size.width - content.width) / 2 + padding, (size.height - content.height) / 2 + padding);
    return WallGeometry(
      size: size,
      cells: [
        for (var row = 0; row < rows; row++)
          for (var column = 0; column < columns; column++)
            Rect.fromLTWH(
              origin.dx + column * (cellWidth + gap),
              origin.dy + row * (cellHeight + gap),
              cellWidth,
              cellHeight,
            ),
      ],
    );
  }

  /// The focus layout: the large cell and a rail of three small cells in
  /// sight (more scroll), below it or beside it.
  factory focus({required double width, double height = double.infinity, double gap = 3, double padding = 3}) {
    // Small cells below: w is a small cell's width.
    final belowByWidth = (width - padding * 2 - gap * 2) / 3;
    final belowByHeight = ((height - padding * 2 - gap) * cellAspect - gap * 2) / 4;
    final below = math.max<double>(0, math.min(belowByWidth, belowByHeight));
    final belowLarge = below * 3 + gap * 2;
    // Small cells beside: s is a small cell's height.
    final besideByWidth = ((width - padding * 2 - gap) / cellAspect - gap * 2) / 4;
    final besideByHeight = (height - padding * 2 - gap * 2) / 3;
    final beside = math.max<double>(0, math.min(besideByWidth, besideByHeight));
    final besideLarge = (beside * 3 + gap * 2) * cellAspect;
    if (belowLarge >= besideLarge) {
      final largeHeight = belowLarge / cellAspect;
      final smallHeight = below / cellAspect;
      final content = Size(belowLarge + padding * 2, largeHeight + gap + smallHeight + padding * 2);
      final size = Size(width, height.isFinite ? height : content.height);
      final origin = Offset((size.width - content.width) / 2 + padding, (size.height - content.height) / 2 + padding);
      return WallGeometry(
        size: size,
        cells: [Rect.fromLTWH(origin.dx, origin.dy, belowLarge, largeHeight)],
        rail: Rect.fromLTWH(origin.dx, origin.dy + largeHeight + gap, belowLarge, smallHeight),
        railExtent: below + gap,
      );
    }
    final largeHeight = beside * 3 + gap * 2;
    final smallWidth = beside * cellAspect;
    final content = Size(besideLarge + gap + smallWidth + padding * 2, largeHeight + padding * 2);
    final size = Size(width, height.isFinite ? height : content.height);
    final origin = Offset((size.width - content.width) / 2 + padding, (size.height - content.height) / 2 + padding);
    return WallGeometry(
      size: size,
      cells: [Rect.fromLTWH(origin.dx, origin.dy, besideLarge, largeHeight)],
      rail: Rect.fromLTWH(origin.dx + besideLarge + gap, origin.dy, smallWidth, largeHeight),
      railVertical: true,
      railExtent: beside + gap,
    );
  }

  /// The wall's size: the area, or the content's height when the area had
  /// none.
  final Size size;

  /// The plain layouts' cells in order; the focus layout's large cell.
  final List<Rect> cells;

  /// The focus layout's rail of small cells (its viewport), else null.
  final Rect? rail;

  /// The rail runs down (small cells beside the large one).
  final bool railVertical;

  /// One rail item along the rail: a small cell and the gap after it.
  final double railExtent;

  /// The cell that got the large rect in a 1+3 template; 0 elsewhere.
  final int largeCell;

  /// The width the cells take (the wall without its empty sides).
  double get contentWidth {
    var left = double.infinity;
    var right = 0.0;
    for (final rect in [...cells, ?rail]) {
      left = math.min(left, rect.left);
      right = math.max(right, rect.right);
    }
    return left.isFinite ? right - left : 0;
  }

  /// The height the cells actually take. A portrait screen uses this to size
  /// the wall by its streams instead of by the old fixed 16:9 cell shape.
  double get contentHeight {
    final rects = [...cells, ?rail];
    if (rects.isEmpty) return 0;
    var top = double.infinity;
    var bottom = 0.0;
    for (final rect in rects) {
      top = math.min(top, rect.top);
      bottom = math.max(bottom, rect.bottom);
    }
    return bottom - top;
  }
}
