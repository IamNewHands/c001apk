// ignore_for_file: constant_identifier_names

enum TabType {
  FOLLOW,
  APP,
  FEED,
  HOT,
  TOPIC,
  PRODUCT,
  COOLPIC,
  NONE;

  String get label => switch (this) {
        FOLLOW => '关注',
        APP => '应用',
        FEED => '动态',
        HOT => '热门',
        TOPIC => '话题',
        PRODUCT => '数码',
        COOLPIC => '酷图',
        NONE => '其他',
      };

  // Explicit persisted IDs: enum positions are also used by return-to-top events.
  String get storageId => switch (this) {
        APP => 'app',
        FEED => 'feed',
        HOT => 'hot',
        TOPIC => 'topic',
        PRODUCT => 'product',
        COOLPIC => 'coolpic',
        FOLLOW => 'follow',
        NONE => 'none',
      };
}

class HomeTabConfiguration {
  HomeTabConfiguration(List<TabType> order, Set<TabType> hidden)
      : order = List.unmodifiable(order),
        hidden = Set.unmodifiable(hidden.difference({TabType.FEED}));

  static const storageKey = 'homeTabs';
  static const defaultOrder = [
    TabType.APP,
    TabType.FEED,
    TabType.HOT,
    TabType.TOPIC,
    TabType.PRODUCT,
    TabType.COOLPIC,
  ];

  final List<TabType> order;
  final Set<TabType> hidden;

  factory HomeTabConfiguration.fromStored(Object? value) {
    final order = <TabType>[];
    final hidden = <TabType>{};
    if (value is Map) {
      final storedOrder = value['order'];
      if (storedOrder is List) {
        for (final id in storedOrder) {
          for (final tab in defaultOrder) {
            if (id == tab.storageId && !order.contains(tab)) order.add(tab);
          }
        }
      }
      final storedHidden = value['hidden'];
      if (storedHidden is List) {
        for (final tab in defaultOrder) {
          if (storedHidden.contains(tab.storageId)) hidden.add(tab);
        }
      }
    }
    order.addAll(defaultOrder.where((tab) => !order.contains(tab)));
    return HomeTabConfiguration(order, hidden);
  }

  List<TabType> available({required bool android}) =>
      order.where((tab) => android || tab != TabType.APP).toList();

  List<TabType> visible({required bool android}) => available(android: android)
      .where((tab) => !hidden.contains(tab))
      .toList();

  Map<String, Object> toStored() => {
        'order': order.map((tab) => tab.storageId).toList(),
        'hidden': hidden.map((tab) => tab.storageId).toList(),
      };
}
