import 'package:flutter/material.dart';
import 'package:live_ui/src/theme/motion.dart';

/// Pages pushed and popped with a spring (A03.5): the new page slides in
/// from the right with a soft shadow on its edge, the page under it moves a
/// quarter to the left under a light shade. Only positions and painted
/// shades change, no page is faded: Flutter's fade-forwards transition
/// (3.x's, R01.3) drew both pages into offscreen layers every frame, and
/// over a playing video that missed the frame at 120 Hz for most of the
/// room's opening.
class SpringPageTransitionsBuilder extends PageTransitionsBuilder {
  /// Creates the builder.
  const new();

  /// How long a push takes.
  static const Duration duration = Duration(milliseconds: 450);

  /// How long a pop takes.
  static const Duration reverseDuration = Duration(milliseconds: 400);

  @override
  Duration get transitionDuration => duration;

  @override
  Duration get reverseTransitionDuration => reverseDuration;

  @override
  Widget buildTransitions<T>(
    PageRoute<T>? route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => SpringPageTransition(animation: animation, secondaryAnimation: secondaryAnimation, child: child);
}

/// The transition of [SpringPageTransitionsBuilder]; with
/// [secondaryAnimation] at rest only the page's own slide (the live room,
/// whose page under it stays put).
class SpringPageTransition extends StatelessWidget {
  /// Creates the transition.
  const new({required this.animation, required this.secondaryAnimation, required this.child, super.key});

  /// This page coming in (0 → 1) or going out (1 → 0).
  final Animation<double> animation;

  /// The next page coming over this one (0 → 1) or leaving it (1 → 0).
  final Animation<double> secondaryAnimation;

  /// The page.
  final Widget child;

  static final Curve _in = SpringCurve(AppMotion.pageTransitionSpring, SpringPageTransitionsBuilder.duration);
  static final Curve _out = SpringCurve(
    AppMotion.pageTransitionSpring,
    SpringPageTransitionsBuilder.reverseDuration,
  ).flipped;

  /// How far the page under moves: a quarter of the width.
  static const double underShift = 0.25;

  /// How dark the page under gets.
  static const double underShade = 0.16;

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final enter = CurvedAnimation(parent: animation, curve: _in, reverseCurve: _out);
    final under = CurvedAnimation(parent: secondaryAnimation, curve: _in, reverseCurve: _out);
    return SlideTransition(
      position: under.drive(Tween(begin: Offset.zero, end: Offset(rtl ? underShift : -underShift, 0))),
      transformHitTests: false,
      child: SlideTransition(
        position: enter.drive(Tween(begin: Offset(rtl ? -1 : 1, 0), end: Offset.zero)),
        child: CustomPaint(
          painter: _EdgeShadowPainter(enter, rtl: rtl),
          foregroundPainter: _ShadePainter(under),
          child: child,
        ),
      ),
    );
  }
}

/// The splash page leaving to the leading side (A06.4): the start-up's
/// reveal, where home is already built under it (its router nests the two
/// routes in one location, R01.3), so the first frames of the animation do
/// not carry home's first build, its follows and its covers.
///
/// Only this page moves, with a slide and without a fade, and the page under
/// it is left to its own transition: two full pages painted a frame at a
/// time is what the spring's fade-forwards predecessor cost.
class SplashExitTransition extends StatelessWidget {
  /// Creates the transition.
  const new({required this.animation, required this.child, super.key});

  /// How long the splash takes to leave: the push's 450 ms.
  static const Duration duration = SpringPageTransitionsBuilder.duration;

  /// This page leaving (1 → 0).
  final Animation<double> animation;

  /// The page.
  final Widget child;

  // The spring as it comes back: fast as it lets go, settling at the end
  // (the push's curve, turned around).
  static final Curve _out = SpringCurve(AppMotion.pageTransitionSpring, duration).flipped;

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return SlideTransition(
      position: animation
          .drive(CurveTween(curve: _out))
          .drive(Tween(begin: Offset(rtl ? 1 : -1, 0), end: Offset.zero)),
      child: child,
    );
  }
}

/// A shadow just outside the leading edge of a page sliding in, fading as
/// it settles: a gradient, cheaper than a blurred shadow.
class _EdgeShadowPainter extends CustomPainter {
  new(this.animation, {required this.rtl}) : super(repaint: animation);

  final Animation<double> animation;
  final bool rtl;

  static const double width = 16;

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    if (t <= 0 || t >= 1) return;
    final alpha = 0.18 * (1 - t);
    final rect = rtl ? Rect.fromLTWH(size.width, 0, width, size.height) : Rect.fromLTWH(-width, 0, width, size.height);
    final paint = Paint()
      ..shader = LinearGradient(
        begin: rtl ? Alignment.centerLeft : Alignment.centerRight,
        end: rtl ? Alignment.centerRight : Alignment.centerLeft,
        colors: [
          Colors.black.withValues(alpha: alpha),
          Colors.black.withValues(alpha: 0),
        ],
      ).createShader(rect);
    canvas.drawRect(rect, paint);
  }

  // Paint only: a page leaving under a tap must not catch it (M13.16).
  @override
  bool hitTest(Offset position) => false;

  @override
  bool shouldRepaint(_EdgeShadowPainter oldDelegate) => oldDelegate.animation != animation || oldDelegate.rtl != rtl;
}

/// The light shade over a page while the next one covers it.
class _ShadePainter extends CustomPainter {
  new(this.animation) : super(repaint: animation);

  final Animation<double> animation;

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    if (t <= 0) return;
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Colors.black.withValues(alpha: SpringPageTransition.underShade * t),
    );
  }

  @override
  bool hitTest(Offset position) => false;

  @override
  bool shouldRepaint(_ShadePainter oldDelegate) => oldDelegate.animation != animation;
}
