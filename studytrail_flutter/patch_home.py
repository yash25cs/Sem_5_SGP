import sys
import re

with open(r'lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Add imports
content = content.replace(
    "import 'package:flutter/material.dart';",
    "import 'package:flutter/material.dart';\nimport 'package:flutter/services.dart';\nimport 'package:confetti/confetti.dart';"
)

# Add ConfettiController to _HomeScreenState
confetti_init = """class _HomeScreenState extends State<HomeScreen> {
  late ConfettiController _confetti;

  @override
  void initState() {
    super.initState();
    _confetti = ConfettiController(duration: const Duration(seconds: 2));
    // Deferred: the store notifies listeners, which can't happen during build."""
content = content.replace(
    """class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Deferred: the store notifies listeners, which can't happen during build.""",
    confetti_init
)

# Add dispose
dispose_block = """
  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  /// "Good morning"""
content = content.replace(
    """
  /// "Good morning""",
    dispose_block
)

# Modify _toggle
toggle_replacement = """  Future<void> _toggle(DailyTask task) async {
    final isCompleting = !task.done;
    if (isCompleting) HapticFeedback.lightImpact();

    await context.read<HomeStore>().toggleTask(task);
    
    if (mounted && isCompleting) {
      final store = context.read<HomeStore>();
      if (store.doneCount == store.tasks.length && store.tasks.isNotEmpty) {
        _confetti.play();
        HapticFeedback.heavyImpact();
      }
    }

    if (!mounted || task.milestoneTaskId == null) return;
    await context.read<RoadmapStore>().load();
  }"""

content = re.sub(
    r"  Future<void> _toggle\(DailyTask task\) async \{.*?    \}\n",
    toggle_replacement + "\n",
    content,
    flags=re.DOTALL
)

# Wrap RefreshIndicator in Stack for Confetti
stack_replacement = """    return Stack(
      children: [
        RefreshIndicator("""
content = content.replace(
    "    return RefreshIndicator(",
    stack_replacement
)

stack_end = """        ),
        Align(
          alignment: Alignment.topCenter,
          child: ConfettiWidget(
            confettiController: _confetti,
            blastDirectionality: BlastDirectionality.explosive,
            emissionFrequency: 0.05,
            numberOfParticles: 25,
            maxBlastForce: 20,
            minBlastForce: 8,
            gravity: 0.2,
          ),
        ),
      ],
    );"""

content = re.sub(
    r"        child: ListView\(.*?        \),\n      \);",
    lambda m: m.group(0)[:-2] + stack_end,
    content,
    flags=re.DOTALL
)

with open(r'lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)
