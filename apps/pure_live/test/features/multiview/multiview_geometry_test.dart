import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/features/multiview/logic/multiview_controller.dart';
import 'package:pure_live/features/multiview/logic/multiview_geometry.dart';

void _expect16by9(Iterable<Rect> rects) {
  for (final rect in rects) {
    expect(rect.width / rect.height, moreOrLessEquals(16 / 9, epsilon: 0.01), reason: '$rect');
  }
}

void main() {
  test('issue #32: four ordered 16:9 pictures in one column at every window size', () {
    final vertical =
        MultiviewLayout.values.where((value) => value.name == 'vertical').firstOrNull ?? MultiviewLayout.quad;
    for (final size in [const Size(1080, 1920), const Size(1280, 800), const Size(393, 852), const Size(740, 360)]) {
      final wall = WallGeometry.of(vertical, width: size.width, height: size.height);
      expect(wall.cells, hasLength(4));
      _expect16by9(wall.cells);
      for (var index = 0; index < 4; index++) {
        final cell = wall.cells[index];
        expect(cell.left, wall.cells.first.left);
        expect(cell.right, lessThanOrEqualTo(size.width));
        expect(cell.bottom, lessThanOrEqualTo(size.height));
        if (index > 0) expect(cell.top, greaterThan(wall.cells[index - 1].bottom));
      }
    }
  });

  test('the most cells follow the device (UI_PLAN §9.3)', () {
    expect(multiviewMaxCells(mobile: true, processors: 16), 4);
    expect(multiviewMaxCells(mobile: false, processors: 8), MultiviewController.desktopMaxCells);
    expect(multiviewMaxCells(mobile: false, processors: 6), 6);
    expect(multiviewMaxCells(mobile: false, processors: 4), 4);
  });

  test('rail items in sight (3.x focus_rail_visibility)', () {
    expect(visibleRailRange(count: 5, offset: 0, viewport: 300, extent: 100), (0, 3));
    expect(visibleRailRange(count: 5, offset: 150, viewport: 300, extent: 100), (1, 5));
    expect(visibleRailRange(count: 5, offset: 0, viewport: 0, extent: 100), (0, 0));
    expect(visibleRailRange(count: 0, offset: 0, viewport: 300, extent: 100), (0, 0));
  });

  test('portrait: 16:9 cells as tall as the width wants; 1×2 one above the other (c2)', () {
    final quad = WallGeometry.of(MultiviewLayout.quad, width: 393);
    expect(quad.cells, hasLength(4));
    _expect16by9(quad.cells);
    expect(quad.cells[0].width, moreOrLessEquals((393 - 9) / 2));
    expect(quad.size.height, moreOrLessEquals(quad.cells[0].height * 2 + 9));
    expect(quad.cells[1].left, greaterThan(quad.cells[0].right));
    expect(quad.cells[2].top, greaterThan(quad.cells[0].bottom));

    final dual = WallGeometry.of(MultiviewLayout.dual, width: 393, height: 364);
    _expect16by9(dual.cells);
    expect(dual.cells[1].top, greaterThan(dual.cells[0].bottom), reason: 'above each other');
    expect(dual.cells[0].left, dual.cells[1].left);

    final focus = WallGeometry.of(MultiviewLayout.focus, width: 393);
    _expect16by9(focus.cells);
    expect(focus.cells.single.width, moreOrLessEquals(393 - 6));
    expect(focus.railVertical, isFalse);
    expect(focus.rail!.top, greaterThan(focus.cells.single.bottom));
    // Three small cells fill the rail.
    expect(focus.rail!.width, moreOrLessEquals(focus.railExtent * 3 - 3));
  });

  test('landscape: side by side; the 1+3 rail beside the large cell; centred in the area', () {
    final dual = WallGeometry.of(MultiviewLayout.dual, width: 612, height: 313);
    _expect16by9(dual.cells);
    expect(dual.cells[1].left, greaterThan(dual.cells[0].right));

    final quad = WallGeometry.of(MultiviewLayout.quad, width: 852, height: 393);
    _expect16by9(quad.cells);
    // The height decides; the sides stay black and even.
    final left = quad.cells[0].left;
    final right = 852 - quad.cells[1].right;
    expect(left, moreOrLessEquals(right));
    expect(left, greaterThan(40));

    final focus = WallGeometry.of(MultiviewLayout.focus, width: 852, height: 393);
    expect(focus.railVertical, isTrue);
    expect(focus.rail!.left, greaterThan(focus.cells.single.right));
    expect(focus.rail!.height, moreOrLessEquals(focus.cells.single.height));
    expect(focus.rail!.width / (focus.railExtent - 3), moreOrLessEquals(16 / 9, epsilon: 0.01));
  });

  test('1×2 keeps equal halves with two portrait streams', () {
    final wall = WallGeometry.of(
      MultiviewLayout.dual,
      width: 393,
      height: 393,
      aspects: const [9 / 16, 9 / 16],
    );
    expect(wall.cells, hasLength(2));
    expect(wall.cells[0].width, moreOrLessEquals(wall.cells[1].width, epsilon: 0.01));
    expect(wall.cells[0].height, moreOrLessEquals(wall.cells[1].height, epsilon: 0.01));
    for (final rect in wall.cells) {
      expect(rect.height / rect.width, greaterThan(1.4), reason: '$rect');
    }
    expect(wall.contentHeight, greaterThan(300));
  });

  test('immersive portrait 1+3 composes four cells from the tall canvas', () {
    const aspects = [9 / 16, 16 / 9, 16 / 9, 16 / 9];
    final wall = WallGeometry.of(
      MultiviewLayout.focus,
      width: 480,
      height: 1040,
      aspects: aspects,
    );
    expect(wall.cells, hasLength(4));
    expect(wall.rail, isNull);
    expect(wall.largeCell, 0);
    for (final rect in wall.cells) {
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(480));
      expect(rect.bottom, lessThanOrEqualTo(1040));
      expect(rect.width, greaterThan(480 * 0.12), reason: '$rect');
      expect(rect.height, greaterThan(1040 * 0.05), reason: '$rect');
    }
    // The portrait main keeps its own shape instead of a stretched strip.
    expect(wall.cells[0].width / wall.cells[0].height, closeTo(9 / 16, 0.08));
    for (var i = 1; i < 4; i++) {
      expect(
        wall.cells[0].width * wall.cells[0].height,
        greaterThan(wall.cells[i].width * wall.cells[i].height * 1.05),
      );
    }
  });

  test('immersive portrait 1+3 follows the focused cell', () {
    const aspects = [16 / 9, 9 / 16, 16 / 9, 16 / 9];
    final wall = WallGeometry.of(
      MultiviewLayout.focus,
      width: 480,
      height: 1040,
      aspects: aspects,
      focused: 1,
    );
    expect(wall.cells, hasLength(4));
    expect(wall.largeCell, 1);
    final main = wall.cells[1];
    expect(main.width / main.height, closeTo(9 / 16, 0.08));
    for (final i in [0, 2, 3]) {
      expect(main.width * main.height, greaterThan(wall.cells[i].width * wall.cells[i].height));
    }
  });

  test('immersive portrait 1+3 keeps every cell usable with a mixed set', () {
    const aspects = [9 / 16, 16 / 9, 16 / 9, 9 / 16];
    final wall = WallGeometry.of(
      MultiviewLayout.focus,
      width: 480,
      height: 1040,
      aspects: aspects,
    );
    expect(wall.cells, hasLength(4));
    for (var i = 0; i < 4; i++) {
      final rect = wall.cells[i];
      final shape = rect.width / rect.height;
      final fit = math.min(aspects[i] / shape, shape / aspects[i]);
      expect(fit, greaterThan(0.29), reason: 'cell $i: $rect');
      if (aspects[i] > 1) {
        expect(rect.width, greaterThan(480 * 0.16), reason: 'landscape cell $i: $rect');
      }
    }
  });
}
