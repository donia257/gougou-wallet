import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'ledger.dart';
import 'ui.dart';

class WalletOption<T> {
  const WalletOption(this.value, this.label, {this.icon, this.enabled = true});
  final T value;
  final String label;
  final IconData? icon;
  final bool enabled;
}

Future<T?> walletSheet<T>(BuildContext context, Widget child) async {
  // Clear the editor scope's focus history before the modal captures it.
  // Otherwise popping the sheet restores the amount field and reopens the IME.
  FocusManager.instance.primaryFocus?.unfocus(
    disposition: UnfocusDisposition.scope,
  );
  FocusManager.instance.applyFocusChangesIfNeeded();
  final result = await showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: paper,
    barrierColor: ink.withValues(alpha: 0.28),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
    ),
    clipBehavior: Clip.antiAlias,
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        child: child,
      ),
    ),
  );
  // Popping a route can queue restoration of its previous input focus. Clear
  // that history again before the exit animation completes.
  FocusManager.instance.primaryFocus?.unfocus();
  return result;
}

class WalletSheetFrame extends StatelessWidget {
  const WalletSheetFrame({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.footer,
  });
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? footer;
  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 10),
        Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: muted.withValues(alpha: .22),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 12, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                        color: ink,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 5),
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          color: muted,
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: '关闭',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded, color: muted),
              ),
            ],
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 16),
            child: child,
          ),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 16),
            child: SizedBox(width: double.infinity, child: footer),
          ),
      ],
    ),
  );
}

Future<T?> showWalletChoices<T>(
  BuildContext context, {
  required String title,
  required T selected,
  required List<WalletOption<T>> options,
}) => walletSheet<T>(
  context,
  WalletSheetFrame(
    title: title,
    subtitle: '轻点选项即可应用',
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final option in options)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: selected == option.value
                  ? const Color(0xFFE2EBDF)
                  : Colors.white,
              borderRadius: BorderRadius.circular(18),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                enabled: option.enabled,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                leading: option.icon == null
                    ? null
                    : Icon(option.icon, color: forest),
                title: Text(
                  option.label,
                  style: TextStyle(
                    color: option.enabled ? ink : muted,
                    fontSize: 14,
                    fontWeight: selected == option.value
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                ),
                trailing: Icon(
                  selected == option.value
                      ? Icons.check_circle_rounded
                      : Icons.circle_outlined,
                  color: selected == option.value
                      ? forest
                      : const Color(0xFFD9DFD6),
                  size: 22,
                ),
                onTap: !option.enabled
                    ? null
                    : () => Navigator.pop(context, option.value),
              ),
            ),
          ),
      ],
    ),
  ),
);

class WalletSegments<T> extends StatelessWidget {
  const WalletSegments({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
  });
  final List<WalletOption<T>> options;
  final T selected;
  final ValueChanged<T>? onChanged;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(5),
    decoration: BoxDecoration(
      color: const Color(0xFFE9EDE4),
      borderRadius: BorderRadius.circular(21),
    ),
    child: Row(
      children: [
        for (final item in options)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: WalletPill(
                label: item.label,
                selected: item.value == selected,
                onTap: !item.enabled || onChanged == null
                    ? null
                    : () => onChanged!(item.value),
              ),
            ),
          ),
      ],
    ),
  );
}

class WalletPill extends StatelessWidget {
  const WalletPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    child: Material(
      color: selected ? forest : Colors.white.withValues(alpha: .72),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: selected ? Colors.white : forest),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: onTap == null
                        ? muted
                        : selected
                        ? Colors.white
                        : ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class WalletSelectField extends StatelessWidget {
  const WalletSelectField({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });
  final String label, value;
  final IconData icon;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => panel(
    ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Icon(icon, color: forest),
      title: Text(label, style: const TextStyle(fontSize: 11, color: muted)),
      subtitle: Text(
        value,
        style: const TextStyle(
          fontSize: 15,
          color: ink,
          fontWeight: FontWeight.w600,
        ),
      ),
      trailing: const Icon(Icons.expand_more_rounded, color: muted),
      onTap: onTap,
    ),
  );
}

class WalletFilterCell extends StatelessWidget {
  const WalletFilterCell({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
    this.active = false,
    this.detail,
  });
  final String? detail;
  final String label, value;
  final VoidCallback? onTap;
  final bool active;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: '$label：${detail ?? value}',
    child: Semantics(
      button: true,
      label: '$label：${detail ?? value}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 17),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: onTap == null ? muted : forest,
                    fontSize: 11,
                    fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 14,
                color: muted,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

DateTimeRange walletAllDates() =>
    DateTimeRange(start: DateTime(1900), end: DateTime(2100, 12, 31));
bool isWalletAllDates(DateTimeRange range) => range == walletAllDates();

Map<String, DateTimeRange> walletDatePresets(DateTime now) {
  final today = dayStart(now);
  final monday = DateTime(
    today.year,
    today.month,
    today.day - today.weekday + 1,
  );
  return {
    '全部日期': walletAllDates(),
    '今天': DateTimeRange(start: today, end: today),
    '近三天': DateTimeRange(
      start: DateTime(today.year, today.month, today.day - 2),
      end: today,
    ),
    '本周': DateTimeRange(
      start: monday,
      end: DateTime(monday.year, monday.month, monday.day + 6),
    ),
    '本月': DateTimeRange(
      start: DateTime(now.year, now.month),
      end: DateTime(now.year, now.month + 1, 0),
    ),
    '本年': DateTimeRange(
      start: DateTime(now.year),
      end: DateTime(now.year, 12, 31),
    ),
  };
}

String walletRangeLabel(DateTimeRange range, DateTime now) {
  for (final preset in walletDatePresets(now).entries) {
    if (preset.value == range) return preset.key;
  }
  final start = range.start;
  final end = range.end;
  if (start == end) return '${start.month}/${start.day}';
  if (start.year == end.year && start.month == end.month) {
    return '${start.month}/${start.day}–${end.day}';
  }
  if (start.year == end.year) {
    return '${start.month}/${start.day}–${end.month}/${end.day}';
  }
  return '${twoDigits(start.year % 100)}/${start.month}/${start.day}–${twoDigits(end.year % 100)}/${end.month}/${end.day}';
}

Future<DateTimeRange?> showWalletDateSheet(
  BuildContext context, {
  required DateTimeRange initial,
  bool range = true,
}) => walletSheet<DateTimeRange>(
  context,
  WalletDateSheet(initial: initial, range: range),
);

class WalletDateSheet extends StatefulWidget {
  const WalletDateSheet({super.key, required this.initial, this.range = true});
  final DateTimeRange initial;
  final bool range;
  @override
  State<WalletDateSheet> createState() => _WalletDateSheetState();
}

class _WalletDateSheetState extends State<WalletDateSheet> {
  late DateTime start = dayStart(widget.initial.start);
  late DateTime? end = dayStart(widget.initial.end);
  late DateTime month = isWalletAllDates(widget.initial)
      ? DateTime(DateTime.now().year, DateTime.now().month)
      : DateTime(start.year, start.month);
  bool pickingEnd = false;
  void select(DateTime date) => setState(() {
    if (!widget.range) {
      start = date;
      end = date;
    } else if (!pickingEnd) {
      start = date;
      end = null;
      pickingEnd = true;
    } else {
      if (date.isBefore(start)) {
        end = start;
        start = date;
      } else {
        end = date;
      }
      pickingEnd = false;
    }
  });
  Future<void> chooseMonth() async {
    final result = await walletSheet<DateTime>(
      context,
      WalletMonthSheet(initial: month),
    );
    if (result != null && mounted) setState(() => month = result);
  }

  @override
  Widget build(BuildContext context) {
    final allDates =
        widget.range &&
        end != null &&
        isWalletAllDates(DateTimeRange(start: start, end: end!));
    final count = DateTime(month.year, month.month + 1, 0).day;
    final offset = month.weekday - 1;
    return WalletSheetFrame(
      title: widget.range ? '选择日期范围' : '选择记账日期',
      subtitle: widget.range ? '先选开始日期，再选结束日期；支持跨月选择' : '把生活记在它发生的那一天',
      footer: FilledButton(
        onPressed: end == null
            ? null
            : () => Navigator.pop(
                context,
                DateTimeRange(start: start, end: end!),
              ),
        child: const Text('应用日期'),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.range) ...[
            LayoutBuilder(
              builder: (context, constraints) {
                final columns =
                    constraints.maxWidth < 300 ||
                        MediaQuery.textScalerOf(context).scale(13) > 17
                    ? 2
                    : 3;
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final preset in walletDatePresets(
                      DateTime.now(),
                    ).entries)
                      SizedBox(
                        width:
                            (constraints.maxWidth - (columns - 1) * 8) /
                            columns,
                        child: WalletPill(
                          label: preset.key,
                          selected:
                              start == preset.value.start &&
                              end == preset.value.end,
                          onTap: () => setState(() {
                            start = preset.value.start;
                            end = preset.value.end;
                            month = isWalletAllDates(preset.value)
                                ? DateTime(
                                    DateTime.now().year,
                                    DateTime.now().month,
                                  )
                                : DateTime(start.year, start.month);
                            pickingEnd = false;
                          }),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '自定义日期',
                style: TextStyle(
                  color: ink,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: WalletPill(
                    label: allDates ? '选择开始日期' : '开始  ${dayKey(start)}',
                    selected: !allDates && !pickingEnd,
                    onTap: () => setState(() => pickingEnd = false),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: WalletPill(
                    label: allDates
                        ? '选择结束日期'
                        : end == null
                        ? '请选择结束日期'
                        : '结束  ${dayKey(end!)}',
                    selected: !allDates && pickingEnd,
                    onTap: () => setState(() => pickingEnd = !allDates),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          panel(
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: '日历上个月',
                        onPressed: month.year == 1900 && month.month == 1
                            ? null
                            : () => setState(
                                () => month = DateTime(
                                  month.year,
                                  month.month - 1,
                                ),
                              ),
                        icon: const Icon(Icons.chevron_left_rounded),
                      ),
                      Expanded(
                        child: TextButton(
                          onPressed: chooseMonth,
                          child: Text(
                            '${month.year} 年 ${month.month} 月',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: forest,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '日历下个月',
                        onPressed: month.year == 2100 && month.month == 12
                            ? null
                            : () => setState(
                                () => month = DateTime(
                                  month.year,
                                  month.month + 1,
                                ),
                              ),
                        icon: const Icon(Icons.chevron_right_rounded),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      for (final day in ['一', '二', '三', '四', '五', '六', '日'])
                        Expanded(
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                day,
                                style: const TextStyle(
                                  color: muted,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  LayoutBuilder(
                    builder: (context, constraints) => GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 7,
                        mainAxisExtent:
                            (MediaQuery.textScalerOf(context).scale(14) + 24)
                                .clamp(42, 64),
                      ),
                      itemCount: ((offset + count + 6) ~/ 7) * 7,
                      itemBuilder: (context, index) {
                        final day = index - offset + 1;
                        if (day < 1 || day > count) {
                          return const SizedBox.shrink();
                        }
                        final date = DateTime(month.year, month.month, day);
                        final endpoint =
                            !allDates && (date == start || date == end);
                        final inside =
                            !allDates &&
                            end != null &&
                            date.isAfter(start) &&
                            date.isBefore(end!);
                        final today = date == dayStart(DateTime.now());
                        return Padding(
                          padding: const EdgeInsets.all(2),
                          child: Semantics(
                            selected: endpoint || inside,
                            button: true,
                            label: dayKey(date),
                            child: Material(
                              color: endpoint
                                  ? forest
                                  : inside
                                  ? const Color(0xFFE2EBDF)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                key: ValueKey('calendar-${dayKey(date)}'),
                                onTap: () => select(date),
                                child: Center(
                                  child: Text(
                                    '$day',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: today || endpoint
                                          ? FontWeight.w800
                                          : FontWeight.w500,
                                      color: endpoint
                                          ? Colors.white
                                          : today
                                          ? forest
                                          : ink,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class WalletMonthSheet extends StatefulWidget {
  const WalletMonthSheet({super.key, required this.initial});
  final DateTime initial;
  @override
  State<WalletMonthSheet> createState() => _WalletMonthSheetState();
}

class _WalletMonthSheetState extends State<WalletMonthSheet> {
  late int year = widget.initial.year;
  late int month = widget.initial.month;
  late final yearController = FixedExtentScrollController(
    initialItem: year - 1900,
  );
  late final monthController = FixedExtentScrollController(
    initialItem: month - 1,
  );
  @override
  void dispose() {
    yearController.dispose();
    monthController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => WalletSheetFrame(
    title: '跳转年月',
    footer: FilledButton(
      onPressed: () => Navigator.pop(context, DateTime(year, month)),
      child: const Text('查看这个月'),
    ),
    child: SizedBox(
      height: 210,
      child: Row(
        children: [
          Expanded(
            child: walletWheel(
              key: const ValueKey('year-wheel'),
              controller: yearController,
              count: 201,
              label: (i) => '${1900 + i} 年',
              onChanged: (i) => year = 1900 + i,
            ),
          ),
          Expanded(
            child: walletWheel(
              key: const ValueKey('month-wheel'),
              controller: monthController,
              count: 12,
              label: (i) => '${i + 1} 月',
              onChanged: (i) => month = i + 1,
            ),
          ),
        ],
      ),
    ),
  );
}

Widget walletWheel({
  required Key key,
  required FixedExtentScrollController controller,
  required int count,
  required String Function(int) label,
  required ValueChanged<int> onChanged,
  bool looping = false,
}) => CupertinoTheme(
  data: const CupertinoThemeData(
    primaryColor: forest,
    textTheme: CupertinoTextThemeData(
      pickerTextStyle: TextStyle(
        fontFamily: 'DailySans',
        fontFamilyFallback: ['DailyChinese'],
        color: ink,
        fontSize: 22,
      ),
    ),
  ),
  child: CupertinoPicker(
    key: key,
    scrollController: controller,
    itemExtent: 48,
    looping: looping,
    diameterRatio: 1.6,
    squeeze: 1.1,
    onSelectedItemChanged: onChanged,
    selectionOverlay: const CupertinoPickerDefaultSelectionOverlay(
      background: Color(0x19245748),
    ),
    children: [for (var i = 0; i < count; i++) Center(child: Text(label(i)))],
  ),
);

Future<TimeOfDay?> showWalletTimeSheet(
  BuildContext context,
  TimeOfDay initial,
) => walletSheet<TimeOfDay>(context, WalletTimeSheet(initial: initial));

class WalletTimeSheet extends StatefulWidget {
  const WalletTimeSheet({super.key, required this.initial});
  final TimeOfDay initial;
  @override
  State<WalletTimeSheet> createState() => _WalletTimeSheetState();
}

class _WalletTimeSheetState extends State<WalletTimeSheet> {
  late int hour = widget.initial.hour;
  late int minute = widget.initial.minute;
  late final hourController = FixedExtentScrollController(initialItem: hour);
  late final minuteController = FixedExtentScrollController(
    initialItem: minute,
  );
  @override
  void dispose() {
    hourController.dispose();
    minuteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => WalletSheetFrame(
    title: '选择时间',
    subtitle: '24 小时制 · 上下滑动时、分，可循环选择',
    footer: FilledButton(
      onPressed: () =>
          Navigator.pop(context, TimeOfDay(hour: hour, minute: minute)),
      child: const Text('应用时间'),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            for (final label in ['小时', '分钟'])
              Expanded(
                child: Center(
                  child: Text(
                    label,
                    style: const TextStyle(color: muted, fontSize: 12),
                  ),
                ),
              ),
          ],
        ),
        SizedBox(
          height: 216,
          child: Row(
            children: [
              Expanded(
                child: walletWheel(
                  key: const ValueKey('hour-wheel'),
                  controller: hourController,
                  count: 24,
                  label: (i) => twoDigits(i),
                  looping: true,
                  onChanged: (i) => hour = i,
                ),
              ),
              const Text(':', style: TextStyle(fontSize: 24, color: forest)),
              Expanded(
                child: walletWheel(
                  key: const ValueKey('minute-wheel'),
                  controller: minuteController,
                  count: 60,
                  label: (i) => twoDigits(i),
                  looping: true,
                  onChanged: (i) => minute = i,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
