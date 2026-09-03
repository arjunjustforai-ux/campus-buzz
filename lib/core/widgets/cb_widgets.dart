import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Small shared building blocks that define the CampusBuzz look.
class CbSection extends StatelessWidget {
  const CbSection({super.key, required this.title, this.subtitle, this.action, this.actionLabel, this.child, this.padding = const EdgeInsets.fromLTRB(16, 20, 16, 8)});
  final String title; final String? subtitle, actionLabel; final VoidCallback? action; final Widget? child; final EdgeInsets padding;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: padding,
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: t.titleLarge), if (subtitle != null) Text(subtitle!, style: t.bodySmall)])),
          if (action != null) TextButton(onPressed: action, child: Text(actionLabel ?? 'See all')),
        ]),
      ),
      if (child != null) child!,
    ]);
  }
}

class CbCard extends StatelessWidget {
  const CbCard({super.key, required this.child, this.onTap, this.padding = const EdgeInsets.all(16), this.gradient = false, this.color, this.borderColor});
  final Widget child; final VoidCallback? onTap; final EdgeInsets padding; final bool gradient; final Color? color, borderColor;
  @override
  Widget build(BuildContext context) {
    final body = Container(
      decoration: BoxDecoration(color: gradient ? null : (color ?? CbColors.surface1), gradient: gradient ? CbColors.gradientSoft : null, borderRadius: BorderRadius.circular(18), border: Border.all(color: borderColor ?? CbColors.border)),
      padding: padding,
      child: child,
    );
    if (onTap == null) return body;
    return Material(color: Colors.transparent, child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(18), child: body));
  }
}

class CbChip extends StatelessWidget {
  const CbChip({super.key, required this.label, this.selected = false, this.onTap, this.icon, this.color, this.small = false});
  final String label; final bool selected, small; final VoidCallback? onTap; final IconData? icon; final Color? color;
  @override
  Widget build(BuildContext context) {
    final fg = selected ? CbColors.dark : (color ?? CbColors.textSecondary);
    final chip = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.symmetric(horizontal: small ? 10 : 14, vertical: small ? 5 : 9),
      decoration: BoxDecoration(color: selected ? (color ?? CbColors.lime) : CbColors.surface2, borderRadius: BorderRadius.circular(999), border: Border.all(color: selected ? (color ?? CbColors.lime) : CbColors.border)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: small ? 13 : 16, color: fg), const SizedBox(width: 6)],
        Text(label, style: (small ? Theme.of(context).textTheme.labelSmall : Theme.of(context).textTheme.labelMedium)?.copyWith(color: fg, fontWeight: FontWeight.w700)),
      ]),
    );
    if (onTap == null) return chip;
    return Semantics(button: true, selected: selected, label: label, child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(999), child: chip));
  }
}

/// Status pill with icon + label so colour is never the only signal.
class CbStatusPill extends StatelessWidget {
  const CbStatusPill({super.key, required this.label, required this.color, this.icon});
  final String label; final Color color; final IconData? icon;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(999), border: Border.all(color: color.withValues(alpha: 0.5))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [if (icon != null) ...[Icon(icon, size: 13, color: color), const SizedBox(width: 4)], Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w700))]),
      );
}

CbStatusPill bandPill(String band, {String? label}) {
  final (icon, text) = switch (band) { 'green' => (Icons.check_circle, 'On track'), 'yellow' => (Icons.warning_amber_rounded, 'Watch'), 'red' => (Icons.error, 'Behind'), _ => (Icons.help_outline, 'No data') };
  return CbStatusPill(label: label ?? text, color: CbColors.bandColor(band), icon: icon);
}

/// Dashboard stat tile with label, value, optional delta and textual context.
class CbStat extends StatelessWidget {
  const CbStat({super.key, required this.label, required this.value, this.hint, this.icon, this.color, this.onTap, this.band});
  final String label, value; final String? hint, band; final IconData? icon; final Color? color; final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return CbCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [if (icon != null) ...[Icon(icon, size: 16, color: color ?? CbColors.textTertiary), const SizedBox(width: 6)], Expanded(child: Text(label, style: t.labelMedium, maxLines: 1, overflow: TextOverflow.ellipsis)), if (band != null) bandPill(band!)]),
        const SizedBox(height: 8),
        Text(value, style: t.headlineMedium?.copyWith(color: color ?? CbColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
        if (hint != null) ...[const SizedBox(height: 4), Text(hint!, style: t.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis)],
      ]),
    );
  }
}

class CbCoinBadge extends StatelessWidget {
  const CbCoinBadge({super.key, required this.amount, this.large = false, this.prefix = '+'});
  final int amount; final bool large; final String prefix;
  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: large ? 14 : 8, vertical: large ? 8 : 3),
        decoration: BoxDecoration(color: CbColors.lime, borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.hexagon_rounded, size: large ? 18 : 12, color: CbColors.dark),
          const SizedBox(width: 4),
          Text('$prefix$amount', style: (large ? Theme.of(context).textTheme.titleMedium : Theme.of(context).textTheme.labelSmall)?.copyWith(color: CbColors.dark, fontWeight: FontWeight.w800)),
        ]),
      );
}

/// Brand-styled placeholder when an image is absent.
class CbPosterPlaceholder extends StatelessWidget {
  const CbPosterPlaceholder({super.key, required this.title, this.height = 160, this.seed = 0, this.bottomInset = 0});
  final String title; final double height; final int seed;
  /// Space reserved at the bottom so overlaid chips never sit on the title.
  final double bottomInset;
  @override
  Widget build(BuildContext context) {
    final colors = [[CbColors.orange, const Color(0xFF7A2A0B)], [const Color(0xFF6B8F1A), CbColors.dark], [const Color(0xFF3B1F7A), CbColors.orange], [const Color(0xFF0E5C6B), CbColors.lime]];
    final c = colors[seed.abs() % colors.length];
    return Container(
      height: height,
      decoration: BoxDecoration(gradient: LinearGradient(colors: c, begin: Alignment.topLeft, end: Alignment.bottomRight)),
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
      alignment: Alignment.bottomLeft,
      child: Text(title.toUpperCase(), maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.white.withValues(alpha: 0.92), height: 1.05, letterSpacing: -0.5)),
    );
  }
}

class CbAvatar extends StatelessWidget {
  const CbAvatar({super.key, required this.name, this.url, this.size = 40});
  final String name; final String? url; final double size;
  @override
  Widget build(BuildContext context) {
    final initials = name.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).take(2).map((s) => s[0].toUpperCase()).join();
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: CbColors.surface3,
      foregroundImage: url != null && url!.isNotEmpty ? NetworkImage(url!) : null,
      child: Text(initials.isEmpty ? '?' : initials, style: TextStyle(color: CbColors.limeText, fontWeight: FontWeight.w800, fontSize: size * 0.36)),
    );
  }
}

/// Responsive page width for web dashboards.
class CbPage extends StatelessWidget {
  const CbPage({super.key, required this.title, required this.child, this.actions = const [], this.subtitle, this.maxWidth = 1200, this.scroll = true});
  final String title; final String? subtitle; final Widget child; final List<Widget> actions; final double maxWidth; final bool scroll;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, runSpacing: 8, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: t.headlineMedium), if (subtitle != null) Text(subtitle!, style: t.bodyMedium)]),
        Wrap(spacing: 8, children: actions),
      ]),
    );
    final body = Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [header, Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: child), const SizedBox(height: 40)])));
    return scroll ? SingleChildScrollView(child: body) : body;
  }
}

class CbStatGrid extends StatelessWidget {
  const CbStatGrid({super.key, required this.children, this.minTileWidth = 180});
  final List<Widget> children; final double minTileWidth;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final cols = (c.maxWidth / minTileWidth).floor().clamp(1, 6);
        final w = (c.maxWidth - (cols - 1) * 12) / cols;
        return Wrap(spacing: 12, runSpacing: 12, children: children.map((ch) => SizedBox(width: w, child: ch)).toList());
      });
}

/// Confirmation dialog with required reason (for admin actions).
Future<String?> askReason(BuildContext context, {required String title, String? hint, String confirmLabel = 'Confirm', bool required = true}) async {
  final ctl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(controller: ctl, maxLines: 3, autofocus: true, decoration: InputDecoration(hintText: hint ?? 'Reason (recorded in the audit log)')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () { if (required && ctl.text.trim().isEmpty) return; Navigator.pop(ctx, ctl.text.trim()); }, child: Text(confirmLabel)),
      ],
    ),
  );
}

Future<bool> confirm(BuildContext context, {required String title, String? message, String confirmLabel = 'Confirm', bool destructive = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(style: destructive ? FilledButton.styleFrom(backgroundColor: CbColors.danger) : null, onPressed: () => Navigator.pop(ctx, true), child: Text(confirmLabel)),
      ],
    ),
  );
  return r == true;
}

class CbKeyValue extends StatelessWidget {
  const CbKeyValue(this.k, this.v, {super.key});
  final String k, v;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(width: 140, child: Text(k, style: Theme.of(context).textTheme.bodySmall)), Expanded(child: Text(v, style: Theme.of(context).textTheme.bodyLarge))]));
}
