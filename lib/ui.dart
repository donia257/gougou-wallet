import 'package:flutter/material.dart';

const appVersion = '0.2.1';
const appBuild = 4;
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
  borderRadius: BorderRadius.circular(22),
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
