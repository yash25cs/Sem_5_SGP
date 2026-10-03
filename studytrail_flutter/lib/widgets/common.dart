import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A soft-minimalist container: 24px radius, tonal shadow, white/navy fill.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.color,
    this.radius = 24,
    this.shadow = true,
    this.gradient,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final double radius;
  final bool shadow;
  final Gradient? gradient;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? p.card) : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: shadow ? p.shadow : null,
      ),
      child: child,
    );
    if (onTap == null) return card;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(radius),
      child: card,
    );
  }
}

/// Section header used inside cards: bold title + optional trailing action.
class CardHeader extends StatelessWidget {
  const CardHeader(this.title, {super.key, this.action});
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    // A Wrap rather than a Row: when the title and its action don't fit on one
    // line (a long class name, a large system font) the action drops to the
    // next line instead of overflowing.
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: SizedBox(
        width: double.infinity,
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          runSpacing: 8,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.2)),
            ?action,
          ],
        ),
      ),
    );
  }
}

/// Fully pill-shaped primary action. Variants cover the coral, soft, outline,
/// and danger buttons from the reference.
enum PillVariant { primary, coral, soft, outline, danger }

class PillButton extends StatelessWidget {
  const PillButton(
    this.label, {
    super.key,
    this.icon,
    this.trailingIcon,
    this.onTap,
    this.variant = PillVariant.primary,
    this.expand = true,
  });

  final String label;
  final IconData? icon;
  final IconData? trailingIcon;
  final VoidCallback? onTap;
  final PillVariant variant;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    late Color bg, fg;
    List<BoxShadow>? shadow;
    BoxBorder? border;
    switch (variant) {
      case PillVariant.primary:
        bg = p.primary;
        fg = p.onPrimary;
        shadow = p.glow;
      case PillVariant.coral:
        bg = p.coral;
        fg = Colors.white;
        shadow = p.coralGlow;
      case PillVariant.soft:
        bg = p.coralSoft;
        fg = p.coralInk;
      case PillVariant.outline:
        bg = Colors.transparent;
        fg = p.ink;
        border = Border.all(color: p.line2, width: 1.5);
      case PillVariant.danger:
        bg = p.card;
        fg = p.error;
        border = Border.all(color: p.error.withValues(alpha: 0.4), width: 1.5);
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
            boxShadow: shadow,
            border: border,
          ),
          child: Container(
            width: expand ? double.infinity : null,
            alignment: expand ? Alignment.center : null,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
            // Two buttons side by side on a narrow phone, or a large system
            // font, used to push the label past the pill ("RIGHT OVERFLOWED").
            // When the width is bounded the label now scales down to fit; it
            // never grows, so a button with room looks exactly as before.
            child: LayoutBuilder(builder: (context, constraints) {
              final content = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 20, color: fg),
                    const SizedBox(width: 8),
                  ],
                  Text(label,
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                          color: fg, fontSize: 15, fontWeight: FontWeight.w700)),
                  if (trailingIcon != null) ...[
                    const SizedBox(width: 8),
                    Icon(trailingIcon, size: 20, color: fg)
                  ],
                ],
              );
              return constraints.maxWidth.isFinite
                  ? FittedBox(fit: BoxFit.scaleDown, child: content)
                  : content;
            }),
          ),
        ),
      ),
    );
  }
}

/// Low-contrast chip used for subject filters and small inline labels.
enum ChipTone { neutral, primary, coral, amber, green, error }

class SoftChip extends StatelessWidget {
  const SoftChip(
    this.label, {
    super.key,
    this.icon,
    this.customLeading,
    this.tone = ChipTone.neutral,
    this.small = false,
    this.onTap,
  });

  final String label;
  final IconData? icon;
  final Widget? customLeading;
  final ChipTone tone;
  final bool small;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    late Color bg, fg;
    switch (tone) {
      case ChipTone.neutral:
        bg = p.card2;
        fg = p.ink2;
      case ChipTone.primary:
        bg = p.primarySoft;
        fg = p.onPrimarySoft;
      case ChipTone.coral:
        bg = p.coralSoft;
        fg = p.coralInk;
      case ChipTone.amber:
        bg = p.amberSoft;
        fg = p.onAmber;
      case ChipTone.green:
        bg = p.greenSoft;
        fg = p.green;
      case ChipTone.error:
        bg = p.errorSoft;
        fg = p.onError;
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width - 64),
        padding: EdgeInsets.symmetric(
            horizontal: small ? 10 : 14, vertical: small ? 4 : 8),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (customLeading != null) ...[
              customLeading!,
              const SizedBox(width: 6),
            ] else if (icon != null) ...[
              Icon(icon, size: small ? 14 : 17, color: fg),
              const SizedBox(width: 6)
            ],
            Flexible(
              child: Text(label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: fg,
                      fontSize: small ? 11 : 13,
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Uppercase pill/tag used for subject + difficulty labels on task cards.
class Tag extends StatelessWidget {
  const Tag(this.label, {super.key, required this.bg, required this.fg});
  final String label;
  final Color bg, fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(label.toUpperCase(),
          style: TextStyle(
              color: fg,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4)),
    );
  }
}

/// Rounded-square icon container (subject glyphs, list leading icons).
class IconTile extends StatelessWidget {
  const IconTile(this.icon,
      {super.key, required this.bg, required this.fg, this.size = 44, this.radius = 14});
  final IconData icon;
  final Color bg, fg;
  final double size, radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(radius)),
      child: Icon(icon, color: fg, size: size * 0.5),
    );
  }
}

/// Thin rounded progress bar.
class ProgressTrack extends StatelessWidget {
  const ProgressTrack(this.value, {super.key, required this.color, this.height = 10});
  final double value; // 0..1
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: LinearProgressIndicator(
        value: value,
        minHeight: height,
        backgroundColor: p.card3,
        valueColor: AlwaysStoppedAnimation(color),
      ),
    );
  }
}

/// Circular avatar with an indigo→coral gradient and an initial — the stand-in
/// for a profile photo used across the app.
class GradAvatar extends StatelessWidget {
  const GradAvatar(this.initial, {super.key, this.size = 40, this.colors});
  final String initial;
  final double size;
  final List<Color>? colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors ?? const [Color(0xFF6D7CFF), Color(0xFFFE6F42)],
        ),
      ),
      child: Text(initial,
          style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: size * 0.38)),
    );
  }
}

/// A bottom action bar with a top divider — the sticky footer under
/// onboarding steps and forms.
class FooterBar extends StatelessWidget {
  const FooterBar({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Container(
      decoration: BoxDecoration(
        color: p.card,
        border: Border(top: BorderSide(color: p.line)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
      child: SafeArea(top: false, child: child),
    );
  }
}

/// Circular ghost/outlined icon button used in app bars.
class RoundIconButton extends StatelessWidget {
  const RoundIconButton(this.icon,
      {super.key, this.onTap, this.plain = true, this.color, this.bg});
  final IconData icon;
  final VoidCallback? onTap;
  final bool plain;
  final Color? color, bg;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: plain ? Colors.transparent : (bg ?? p.card),
          border: plain ? null : Border.all(color: p.line),
        ),
        child: Icon(icon, size: 24, color: color ?? p.ink2),
      ),
    );
  }
}
