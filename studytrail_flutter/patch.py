import sys

with open(r'lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

target = "              _HeroStat(daysLeft == null ? '—' : '$daysLeft', 'Days left'),"
replacement = """              if (daysLeft != null && daysLeft <= 7)
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                    decoration: BoxDecoration(
                      color: daysLeft <= 3 ? p.error : const Color(0xFFFFC773),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Text('$daysLeft',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                height: 1.1)),
                        const Text('Days left!',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                )
              else
                _HeroStat(daysLeft == null ? '—' : '$daysLeft', 'Days left'),"""

# The file actually has a special character, let's just find _HeroStat(.*'Days left'),
import re
content = re.sub(r"              _HeroStat\(daysLeft == null \? '.*' : '\$daysLeft', 'Days left'\),", replacement, content)

with open(r'lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)
