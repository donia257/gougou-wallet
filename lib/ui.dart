import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const appVersion = '0.2.3';
const appBuild = 6;
const cardRadius = 22.0;
const walletOverlay = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.dark,
  statusBarBrightness: Brightness.light,
  systemNavigationBarColor: Colors.transparent,
  systemNavigationBarIconBrightness: Brightness.dark,
  systemStatusBarContrastEnforced: false,
  systemNavigationBarContrastEnforced: false,
);
const forest = Color(0xFF245748);
const paper = Color(0xFFF6F5EF);
const ink = Color(0xFF263C34);
const muted = Color(0xFF68786F);
const coral = Color(0xFFAD4E35);
const categoryIcons = <String, IconData>{
  '餐饮': Icons.ramen_dining_rounded,
  '交通': Icons.directions_bus_rounded,
  '购物': Icons.shopping_bag_outlined,
  '日用': Icons.local_florist_outlined,
  '住房': Icons.home_outlined,
  '娱乐': Icons.sports_esports_outlined,
  '医疗': Icons.health_and_safety_outlined,
  '学习': Icons.menu_book_rounded,
  '工资': Icons.work_outline_rounded,
  '奖金': Icons.paid_outlined,
  '红包': Icons.redeem_rounded,
  '兼职': Icons.laptop_rounded,
  '宠物': Icons.pets_rounded,
  '旅行': Icons.flight_takeoff_rounded,
  '运动': Icons.fitness_center_rounded,
  '转账': Icons.swap_horiz_rounded,
  '其他': Icons.grid_view_rounded,
};
IconData categoryIcon(String key) =>
    categoryIcons[key] ?? Icons.grid_view_rounded;

Widget panel(Widget child) => Material(
  color: Colors.white,
  borderRadius: BorderRadius.circular(cardRadius),
  clipBehavior: Clip.antiAlias,
  child: child,
);

Widget sectionTitle(String title, {String? action, VoidCallback? onTap}) => Row(
  children: [
    Expanded(
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
      ),
    ),
    if (action != null) TextButton(onPressed: onTap, child: Text(action)),
  ],
);

Widget emptyState(String title, String subtitle) => panel(
  Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      children: [
        const Icon(Icons.pets_outlined, size: 34, color: forest),
        const SizedBox(height: 14),
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600, color: ink),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, height: 1.7, color: muted),
        ),
      ],
    ),
  ),
);

Future<bool> confirmAction(
  BuildContext context,
  String title,
  String content,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定'),
          ),
        ],
      ),
    ) ??
    false;

void showMessage(BuildContext context, String message) => ScaffoldMessenger.of(
  context,
).showSnackBar(SnackBar(content: Text(message)));

/// Blurs the content behind the chrome and keeps its edge visually light.
class WalletGlassSurface extends StatelessWidget {
  const WalletGlassSurface({
    super.key,
    required this.child,
    this.strength = 1,
    this.bottom = false,
  });
  final Widget child;
  final double strength;
  final bool bottom;

  @override
  Widget build(BuildContext context) {
    final contrast = MediaQuery.highContrastOf(context);
    final alpha = contrast ? 1.0 : strength;
    final colors = bottom
        ? [
            paper.withValues(alpha: 0.45),
            paper.withValues(alpha: 0.78),
            paper.withValues(alpha: 0.92),
          ]
        : [
            Color.lerp(paper, paper.withValues(alpha: 0.90), alpha)!,
            Color.lerp(paper, paper.withValues(alpha: 0.62), alpha)!,
            Color.lerp(paper, paper.withValues(alpha: 0.12), alpha)!,
          ];
    return ClipRRect(
      borderRadius: bottom
          ? const BorderRadius.vertical(top: Radius.circular(26))
          : BorderRadius.zero,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(
          sigmaX: contrast ? 0 : 18 * strength,
          sigmaY: contrast ? 0 : 18 * strength,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: contrast ? [paper, paper, paper] : colors,
              stops: const [0, 0.55, 1],
            ),
            border: bottom
                ? Border(
                    top: BorderSide(
                      color: Colors.white.withValues(alpha: 0.65),
                      width: 0.7,
                    ),
                  )
                : null,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// The expanded page introduction gives way to a centered, pinned brand header.
class WalletSliverHeader extends StatelessWidget {
  const WalletSliverHeader({super.key, required this.expanded});
  final Widget expanded;

  static double expandedExtent(BuildContext context) {
    final painter = TextPainter(
      text: const TextSpan(
        text: '每一笔，都有迹可循。',
        style: TextStyle(
          fontFamily: 'DailySans',
          fontFamilyFallback: ['DailyChinese'],
          fontSize: 25,
          height: 1.4,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: MediaQuery.sizeOf(context).width - 44);
    final height = painter.height;
    painter.dispose();
    final monthHeight = MediaQuery.textScalerOf(context).scale(11) * 2.9;
    return 16 + (monthHeight > 48 ? monthHeight : 48) + 18 + height + 15;
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final height = expandedExtent(context);
    return SliverAppBar(
      pinned: true,
      automaticallyImplyLeading: false,
      expandedHeight: height,
      backgroundColor: Colors.transparent,
      forceMaterialTransparency: true,
      systemOverlayStyle: walletOverlay,
      flexibleSpace: LayoutBuilder(
        builder: (context, constraints) {
          final progress =
              ((height + top - constraints.maxHeight) /
                      (height - kToolbarHeight))
                  .clamp(0.0, 1.0);
          return ClipRect(
            child: Stack(
              children: [
                Positioned.fill(
                  child: WalletGlassSurface(
                    strength: progress,
                    child: const SizedBox.expand(),
                  ),
                ),
                Positioned(
                  top: top + 16 - progress * 24,
                  left: 22,
                  right: 22,
                  child: IgnorePointer(
                    ignoring: progress > 0.5,
                    child: ExcludeSemantics(
                      excluding: progress > 0.5,
                      child: Opacity(
                        opacity: (1 - progress * 2).clamp(0.0, 1.0),
                        child: expanded,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: top,
                  left: 0,
                  right: 0,
                  height: kToolbarHeight,
                  child: IgnorePointer(
                    child: ExcludeSemantics(
                      excluding: progress < 0.5,
                      child: Opacity(
                        opacity: ((progress - 0.5) * 2).clamp(0.0, 1.0),
                        child: Center(
                          child: Row(
                            key: const ValueKey('collapsed-brand'),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(9),
                                child: Image.asset(
                                  'assets/brand/wangwang-wallet-logo.png',
                                  width: 30,
                                  height: 30,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                '汪汪钱包',
                                style: TextStyle(
                                  color: forest,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
