import 'package:flutter/material.dart';

import '../../widgets/bytequest_bottom_nav.dart';

/// Selects an existing main destination without pushing a duplicate screen.
class LearnerNavigationScope extends InheritedWidget {
  const LearnerNavigationScope({
    super.key,
    required this.selectDestination,
    required super.child,
  });

  final ValueChanged<int> selectDestination;

  static LearnerNavigationScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LearnerNavigationScope>();

  @override
  bool updateShouldNotify(LearnerNavigationScope oldWidget) => false;
}

/// Keeps destination state and returns system Back to the last visited tab.
class LearnerNavigationShell extends StatefulWidget {
  const LearnerNavigationShell({super.key, required this.destinations});

  final List<Widget> destinations;

  @override
  State<LearnerNavigationShell> createState() => _LearnerNavigationShellState();
}

class _LearnerNavigationShellState extends State<LearnerNavigationShell> {
  final List<int> _history = [0];

  void _select(int index) {
    if (index == _history.last) return;
    setState(() {
      _history.remove(index);
      _history.add(index);
    });
  }

  @override
  Widget build(BuildContext context) => LearnerNavigationScope(
        selectDestination: _select,
        child: PopScope(
          canPop: _history.length == 1,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && _history.length > 1) {
              setState(() => _history.removeLast());
            }
          },
          child: Scaffold(
            body: IndexedStack(
              index: _history.last,
              children: [
                for (var index = 0; index < widget.destinations.length; index++)
                  TickerMode(
                    enabled: index == _history.last,
                    child: widget.destinations[index],
                  ),
              ],
            ),
            bottomNavigationBar: ByteQuestBottomNav(
              currentIndex: _history.last,
              onTap: _select,
            ),
          ),
        ),
      );
}
