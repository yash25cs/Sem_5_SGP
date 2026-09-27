import sys

with open(r'lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()

new_lines = lines[:351] + [
"          ],\n",
"        ),\n",
"      ),\n",
"      Align(\n",
"        alignment: Alignment.topCenter,\n",
"        child: ConfettiWidget(\n",
"          confettiController: _confetti,\n",
"          blastDirectionality: BlastDirectionality.explosive,\n",
"          emissionFrequency: 0.05,\n",
"          numberOfParticles: 25,\n",
"          maxBlastForce: 20,\n",
"          minBlastForce: 8,\n",
"          gravity: 0.2,\n",
"        ),\n",
"      ),\n",
"    ],\n",
"  );\n",
"  }\n",
"}\n"
] + lines[369:]

with open(r'lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.writelines(new_lines)
