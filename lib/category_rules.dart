import 'ledger.dart';

String fallbackCategory(Ledger ledger, EntryType type) {
  final choices = ledger.categoriesFor(type);
  return choices
      .firstWhere(
        (c) => c.name == (type == EntryType.income ? '其他收入' : '其他'),
        orElse: () => choices.first,
      )
      .id;
}

String recommendCategory(Ledger ledger, EntryType type, String text) {
  final candidates = ledger.categoriesFor(type);
  final normalized = text.toLowerCase();
  final explicit =
      candidates
          .where(
            (c) =>
                c.name.length >= 2 &&
                !c.name.startsWith('其他') &&
                normalized.contains(c.name.toLowerCase()),
          )
          .toList()
        ..sort((a, b) => b.name.length.compareTo(a.name.length));
  if (explicit.isNotEmpty) return explicit.first.id;
  const rules = {
    '餐饮': [
      '餐厅',
      '饭店',
      '咖啡',
      '奶茶',
      '早餐',
      '午餐',
      '晚餐',
      '外卖',
      '美团',
      '饿了么',
      '瑞幸',
      '星巴克',
      '肯德基',
      '麦当劳',
    ],
    '交通': ['滴滴', '打车', '出租车', '地铁', '公交', '火车票', '高铁', '停车', '加油', '出行'],
    '购物': ['淘宝', '京东', '拼多多', '天猫', '服装', '衣服', '鞋子'],
    '日用': ['超市', '便利店', '日用品', '百货', '杂货'],
    '住房': ['房租', '物业', '电费', '水费', '燃气'],
    '医疗': ['医院', '药店', '药房', '门诊', '挂号'],
    '学习': ['书店', '学费', '教材', '课程'],
    '娱乐': ['电影', '影院', '游戏', '门票'],
    '工资': ['工资', '薪资', '薪酬'],
    '奖金': ['奖金', '绩效'],
    '红包': ['红包'],
  };
  for (final category in candidates) {
    if (rules[category.name]?.any(normalized.contains) == true) {
      return category.id;
    }
  }
  return fallbackCategory(ledger, type);
}
