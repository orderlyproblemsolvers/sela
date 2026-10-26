import 'dart:math' as math;

import 'package:animations/animations.dart';
import 'package:flutter/material.dart';

/// Tells the whole app whether to use reduced motion. True when the user
/// switched on "Reduce motion" in Settings OR the system asks for it.
class Motion extends InheritedWidget {
  const Motion({super.key, required this.reduce, required super.child});

  final bool reduce;

  static bool reduced(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<Motion>()?.reduce ?? false;

  @override
  bool updateShouldNotify(Motion old) => reduce != old.reduce;
}

/// A spring expressed the way Apple does it: damping ratio + response.
///
/// damping 1.0 = critically damped (smooth settle, no overshoot) — the
/// default for UI. Below 1.0 it overshoots; only use that when a flick or
/// throw carried momentum.
class SpringCurve extends Curve {
  const SpringCurve({
    this.response = 0.35,
    this.damping = 1.0,
    this.duration = const Duration(milliseconds: 450),
  });

  /// Seconds for the spring to travel (not the same as a duration).
  final double response;
  final double damping;

  /// How long the animation this curve is used in will run.
  final Duration duration;

  @override
  double transformInternal(double t) {
    final w = 2 * math.pi / response;
    final s = t * duration.inMilliseconds / 1000.0;
    if (damping >= 1.0) {
      return 1 - (1 + w * s) * math.exp(-w * s);
    }
    final wd = w * math.sqrt(1 - damping * damping);
    return 1 -
        math.exp(-damping * w * s) *
            (math.cos(wd * s) + (damping * w / wd) * math.sin(wd * s));
  }
}

/// Instant press feedback: shrinks the moment a finger touches down, springs
/// back on release. [restScale] lets a parent hold it smaller (e.g. while a
/// card is selected). Cancels if the finger drags away (scrolling).
class PressScale extends StatefulWidget {
  const PressScale({
    super.key,
    required this.child,
    this.restScale = 1.0,
    this.pressedScale = 0.97,
  });

  final Widget child;
  final double restScale;
  final double pressedScale;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;
  Offset _start = Offset.zero;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final reduce = Motion.reduced(context);
    final scale = reduce
        ? 1.0
        : (_down ? widget.pressedScale * widget.restScale : widget.restScale);

    return Listener(
      onPointerDown: (e) {
        _start = e.position;
        _set(true);
      },
      onPointerMove: (e) {
        if (_down && (e.position - _start).distance > 12) _set(false);
      },
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: scale,
        duration: Duration(milliseconds: _down ? 90 : 420),
        curve: _down ? Curves.easeOut : const SpringCurve(),
        child: widget.child,
      ),
    );
  }
}

/// Page transition used for ordinary pages (Settings): shared axis, or a plain
/// cross-fade when motion is reduced.
class MotionPageTransitionsBuilder extends PageTransitionsBuilder {
  const MotionPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (Motion.reduced(context)) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      );
    }
    return SharedAxisTransition(
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      transitionType: SharedAxisTransitionType.horizontal,
      fillColor: Theme.of(context).colorScheme.surface,
      child: child,
    );
  }
}

/// A plain fade route (used instead of the container transform when motion
/// is reduced).
Route<T> fadeRoute<T>(Widget page) => PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 160),
      reverseTransitionDuration: const Duration(milliseconds: 140),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, animation, __, child) =>
          FadeTransition(opacity: animation, child: child),
    );
