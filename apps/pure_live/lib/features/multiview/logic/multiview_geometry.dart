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
  // 3 landscape + 1 portrait, the portrait large: it keeps the 2/3 slot
  // (65.0 % of the screen, the chosen version) and the three stay 16:9.
  (1, true) => const [
    _Slot(0, 0, 1280, 1080, portrait: true, large: true),
    _Slot(1280, 0, 640, 360),
    _Slot(1280, 360, 640, 360),
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

/// The template's cells for [aspects], in cell order, and the height the
/// four take at this width; null when nothing fits.
(List<Rect>, double)? _templateCells({
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
  final slots = _slotsFor(portraits, aspects[focused] < 1);
  if (slots == null) return null;

  final scale = math.min(inner.width / 1920, inner.height / 1080);
  if (!scale.isFinite || scale <= 0) return null;
  final originX = (inner.width - 1920 * scale) / 2;
  final originY = (inner.height - 1080 * scale) / 2;

  // The focused cell takes the large slot; the others fill by shape, in order.
  final queue = {true: <int>[], false: <int>[]};
  for (var i = 0; i < 4; i++) {
    if (i != focused) queue[aspects[i] < 1 ? true : false]!.add(i);
  }
  final placed = List<Rect?>.filled(4, null);
  for (final slot in slots) {
    final int index;
    if (slot.large) {
      index = focused;
    } else {
      final waiting = queue[slot.portrait]!;
      if (waiting.isEmpty) return null;
      index = waiting.removeAt(0);
    }
    if (placed[index] != null) return null;
    final rect = Rect.fromLTWH(
      originX + slot.left * scale,
      originY + slot.top * scale,
      slot.width * scale,
      slot.height * scale,
    ).deflate(gap / 2);
    if (rect.width <= 0 || rect.height <= 0) return null;
    placed[index] = rect;
  }
  if (placed.contains(null)) return null;
  return ([for (final rect in placed) rect!], 1080 * scale);
}


/// Where the cells of a layout go (docs/A-界面设计/A13-网络电视和多画面界面/A13.2-多画面): 16:9 cells as large
/// as the area lets them be, centred; 1×2 one above the other or side by
/// side, and 1+3 with its small cells below or beside the large one,
/// whichever shows larger pictures.
final class WallGeometry {
  /// Creates the geometry.
  const new({required this.size, required this.cells, this.rail, this.railVertical = false, this.railExtent = 0});

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
    if (layout == MultiviewLayout.focus) {
      if (aspects != null && aspects.length == 4) {
        final across = math.max<double>(0, width - padding * 2);
        final inner = Size(
          across,
          height.isFinite ? math.max<double>(0, height - padding * 2) : across * 1080 / 1920,
        );
        final template = _templateCells(aspects: aspects, focused: focused, inner: inner, gap: gap);
        if (template != null) {
          final (cells, contentHeight) = template;
          return WallGeometry(
            size: Size(width, height.isFinite ? height : contentHeight + padding * 2),
            cells: cells,
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
}
