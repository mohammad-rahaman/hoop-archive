import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../features/compare/compare_screen.dart';
import '../features/home/home_screen.dart';
import '../features/not_found_screen.dart';
import '../features/players/players_screen.dart';
import '../features/players/profile_screen.dart';
import 'theme.dart';

/// App router: three top-level tabs (Archive, Players, Compare), each with its
/// own navigation stack, so a player profile pushed from Players keeps its
/// place when the user hops to Compare and back. A friendly not-found page
/// handles unknown or malformed routes (e.g. a stale deep link).
final appRouter = GoRouter(
  initialLocation: '/',
  errorBuilder: (context, state) =>
      NotFoundScreen(location: state.uri.toString()),
  routes: [
    StatefulShellRoute(
      builder: (context, state, shell) => AppShell(shell: shell),
      navigatorContainerBuilder: (context, shell, children) => _SwipePager(
        currentIndex: shell.currentIndex,
        onSwitch: (i) => shell.goBranch(i),
        children: children,
      ),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/',
              name: 'home',
              builder: (context, state) => const HomeScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/players',
              name: 'players',
              builder: (context, state) => const PlayersScreen(),
              routes: [
                GoRoute(
                  path: ':id',
                  name: 'player',
                  builder: (context, state) {
                    final id =
                        int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
                    return ProfileScreen(
                      playerId: id,
                      initialSeason: state.uri.queryParameters['season'],
                    );
                  },
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/compare',
              name: 'compare',
              builder: (context, state) => CompareScreen(
                initialAId: int.tryParse(state.uri.queryParameters['a'] ?? ''),
                initialBId: int.tryParse(state.uri.queryParameters['b'] ?? ''),
                initialASeason: state.uri.queryParameters['as'],
                initialBSeason: state.uri.queryParameters['bs'],
              ),
            ),
          ],
        ),
      ],
    ),
  ],
);

/// Hosts the tab bar. Tapping the active tab pops it back to its root, as on
/// every iOS app. The branch underneath eases in on a switch, and a highlight
/// box glides to the chosen tab.
class AppShell extends StatelessWidget {
  final StatefulNavigationShell shell;
  const AppShell({super.key, required this.shell});

  static const _tabs = <_TabSpec>[
    _TabSpec('Archive', CupertinoIcons.archivebox, CupertinoIcons.archivebox_fill),
    _TabSpec('Players', CupertinoIcons.person_2, CupertinoIcons.person_2_fill),
    _TabSpec('Compare', CupertinoIcons.arrow_right_arrow_left,
        CupertinoIcons.arrow_right_arrow_left),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: _GlideTabBar(
        tabs: _tabs,
        currentIndex: shell.currentIndex,
        onTap: (i) =>
            shell.goBranch(i, initialLocation: i == shell.currentIndex),
      ),
    );
  }
}

class _TabSpec {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  const _TabSpec(this.label, this.icon, this.activeIcon);
}

/// Lays the three branches side by side and lets you drag between them. The
/// current branch follows your finger; a flick or a past-a-third drag commits
/// to the neighbour and the page slides fully across, otherwise it springs
/// back. A tab tap slides the same way. Off-screen branches are kept mounted
/// (state preserved, like an IndexedStack) and their tickers paused. Honors
/// Reduce Motion by jumping instead of sliding.
class _SwipePager extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onSwitch;
  final List<Widget> children;
  const _SwipePager({
    required this.currentIndex,
    required this.onSwitch,
    required this.children,
  });

  @override
  State<_SwipePager> createState() => _SwipePagerState();
}

class _SwipePagerState extends State<_SwipePager>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );
  double _drag = 0; // px the stack is offset from the resting position.
  double _width = 0;
  double _from = 0, _to = 0;
  int _targetIndex = 0;
  bool _committing = false;

  @override
  void initState() {
    super.initState();
    _targetIndex = widget.currentIndex;
    _ctrl
      ..addListener(() {
        setState(() {
          _drag = _from + (_to - _from) * Curves.easeOutCubic.transform(_ctrl.value);
        });
      })
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) _onSettled();
      });
  }

  @override
  void didUpdateWidget(_SwipePager old) {
    super.didUpdateWidget(old);
    if (widget.currentIndex != old.currentIndex) {
      if (_committing) {
        // Our own drag/flick commit: the new branch is already in view, so
        // snap the offset to zero without a second animation.
        _committing = false;
        _drag = 0;
      } else {
        // Driven from outside (a tab tap or bar drag): slide the new branch in.
        // Point the settle target at the current index so this animation's
        // completion handler doesn't re-commit to a stale drag target and
        // bounce the branch back.
        _targetIndex = widget.currentIndex;
        final noMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
        if (noMotion || _width == 0) {
          _drag = 0;
        } else {
          _drag = widget.currentIndex > old.currentIndex ? _width : -_width;
          _animate(_drag, 0);
        }
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _animate(double from, double to) {
    _from = from;
    _to = to;
    _ctrl
      ..value = 0
      ..forward();
  }

  void _onSettled() {
    if (_targetIndex != widget.currentIndex) {
      _committing = true;
      widget.onSwitch(_targetIndex); // didUpdateWidget zeroes _drag seamlessly.
    } else {
      setState(() => _drag = 0);
    }
  }

  void _update(double dx) {
    final atStart = widget.currentIndex == 0;
    final atEnd = widget.currentIndex == widget.children.length - 1;
    // Rubber-band when there is no neighbour to reveal.
    final resist = (atStart && _drag + dx > 0) || (atEnd && _drag + dx < 0);
    setState(() => _drag += resist ? dx * 0.32 : dx);
  }

  void _end(double velocity) {
    if (_width == 0) return;
    final threshold = _width * 0.32;
    final last = widget.children.length - 1;
    var target = widget.currentIndex;
    var targetDrag = 0.0;
    if ((_drag <= -threshold || velocity < -650) && widget.currentIndex < last) {
      target = widget.currentIndex + 1;
      targetDrag = -_width;
    } else if ((_drag >= threshold || velocity > 650) && widget.currentIndex > 0) {
      target = widget.currentIndex - 1;
      targetDrag = _width;
    }
    _targetIndex = target;
    final noMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (noMotion) {
      _drag = targetDrag;
      _onSettled();
    } else {
      _animate(_drag, targetDrag);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _width = constraints.maxWidth;
        final neighbor = _drag > 0
            ? widget.currentIndex - 1
            : (_drag < 0 ? widget.currentIndex + 1 : -1);
        return GestureDetector(
          onHorizontalDragStart: (_) => _ctrl.stop(),
          onHorizontalDragUpdate: (d) => _update(d.delta.dx),
          onHorizontalDragEnd: (d) => _end(d.primaryVelocity ?? 0),
          child: Stack(
            children: [
              for (var i = 0; i < widget.children.length; i++)
                _layer(i, neighbor),
            ],
          ),
        );
      },
    );
  }

  Widget _layer(int i, int neighbor) {
    final current = i == widget.currentIndex;
    final visible = current || i == neighbor;
    final offset = (i - widget.currentIndex) * _width + _drag;
    return Offstage(
      offstage: !visible,
      child: Transform.translate(
        offset: Offset(offset, 0),
        child: TickerMode(
          enabled: current,
          child: IgnorePointer(ignoring: !current, child: widget.children[i]),
        ),
      ),
    );
  }
}

/// A three-slot bottom bar with a rounded highlight box that glides to the
/// active tab. Active icon and label are volt; the rest sit quiet.
class _GlideTabBar extends StatelessWidget {
  final List<_TabSpec> tabs;
  final int currentIndex;
  final ValueChanged<int> onTap;
  const _GlideTabBar({
    required this.tabs,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final noMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    const barHeight = 56.0;
    const boxInset = 8.0; // horizontal gap from the slot edge to the box.

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Hue.ground,
        border: Border(top: BorderSide(color: Hue.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final slot = constraints.maxWidth / tabs.length;
            // Drag across the bar to move between tabs: map the finger's x to a
            // slot and switch when it lands on a new one. A raw Listener reads
            // pointer moves without entering the gesture arena, so it never
            // steals taps from the buttons underneath.
            void switchToX(double dx) {
              final i = (dx / slot).floor().clamp(0, tabs.length - 1);
              if (i != currentIndex) {
                HapticFeedback.selectionClick();
                onTap(i);
              }
            }

            return Listener(
              onPointerMove: (e) => switchToX(e.localPosition.dx),
              child: SizedBox(
                height: barHeight,
                child: Stack(
                  children: [
                    // Highlight box, centred in the active slot so its side
                    // margins are equal on every tab (edge tabs included).
                    AnimatedPositioned(
                      duration: noMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 340),
                      curve: Curves.easeOutCubic,
                      left: currentIndex * slot + boxInset,
                      top: (barHeight - 44) / 2,
                      width: slot - boxInset * 2,
                      height: 44,
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          color: Hue.raised,
                          borderRadius: BorderRadius.all(Radius.circular(14)),
                          border: Border.fromBorderSide(
                            BorderSide(color: Hue.hairlineStrong),
                          ),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        for (var i = 0; i < tabs.length; i++)
                          Expanded(
                            child: _TabButton(
                              spec: tabs[i],
                              active: i == currentIndex,
                              onTap: () {
                                if (i != currentIndex) {
                                  HapticFeedback.selectionClick();
                                }
                                onTap(i);
                              },
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final _TabSpec spec;
  final bool active;
  final VoidCallback onTap;
  const _TabButton({
    required this.spec,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? Hue.volt : Hue.textLo;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: double.infinity,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(active ? spec.activeIcon : spec.icon, size: 22, color: color),
            const SizedBox(height: 3),
            Text(
              spec.label,
              style: Txt.label.copyWith(
                fontSize: 9.5,
                letterSpacing: 0.6,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
