import 'package:flutter/widgets.dart';

/// An [IndexedStack] that builds each child the first time it is shown, then
/// keeps it — scroll position, state and all — like an ordinary one.
///
/// The bottom navigation used a plain [IndexedStack], which builds every tab
/// at once: each tab's `initState` loads its data, so a launch fired about 27
/// requests for five screens while the student looked at one, all competing
/// with Home's on a ~300 ms link to the database.
class LazyIndexedStack extends StatefulWidget {
  const LazyIndexedStack({
    super.key,
    required this.index,
    required this.children,
  });

  final int index;
  final List<Widget> children;

  @override
  State<LazyIndexedStack> createState() => _LazyIndexedStackState();
}

class _LazyIndexedStackState extends State<LazyIndexedStack> {
  late final Set<int> _built = {widget.index};

  @override
  void didUpdateWidget(LazyIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    _built.add(widget.index);
  }

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: widget.index,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          _built.contains(i) ? widget.children[i] : const SizedBox.shrink(),
      ],
    );
  }
}
