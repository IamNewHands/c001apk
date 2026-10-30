import 'dart:io';

import 'package:flutter/material.dart';

import '../../constants/home_tab.dart';
import '../../utils/storage_util.dart';

class HomeTabsPage extends StatefulWidget {
  const HomeTabsPage({super.key});

  @override
  State<HomeTabsPage> createState() => _HomeTabsPageState();
}

class _HomeTabsPageState extends State<HomeTabsPage> {
  late HomeTabConfiguration _draft = HomeTabConfiguration.fromStored(
      GStorage.settings.get(HomeTabConfiguration.storageKey));
  bool _saving = false;
  String? _error;

  void _move(TabType tab, int delta) {
    final available = _draft.available(android: Platform.isAndroid);
    final index = available.indexOf(tab);
    final other = available[index + delta];
    final order = _draft.order.toList();
    final from = order.indexOf(tab);
    final to = order.indexOf(other);
    order[from] = other;
    order[to] = tab;
    setState(() => _draft = HomeTabConfiguration(order, _draft.hidden));
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await GStorage.settings
          .put(HomeTabConfiguration.storageKey, _draft.toStored());
      if (mounted) Navigator.of(context).pop(_draft);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '保存失败，请重试';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _draft.available(android: Platform.isAndroid);
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(title: const Text('编辑主页分类'), actions: [
          TextButton(
              onPressed: _saving ? null : _save, child: const Text('完成')),
        ]),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(padding: const EdgeInsets.all(16), children: [
              const Text('选择要显示的分类，使用箭头调整顺序。动态始终保留。'),
              const SizedBox(height: 12),
              for (var i = 0; i < tabs.length; i++)
                Card(
                  key: ValueKey(tabs[i]),
                  child: ListTile(
                    leading: Checkbox(
                      value: !_draft.hidden.contains(tabs[i]),
                      onChanged: _saving || tabs[i] == TabType.FEED
                          ? null
                          : (value) {
                              final hidden = _draft.hidden.toSet();
                              value!
                                  ? hidden.remove(tabs[i])
                                  : hidden.add(tabs[i]);
                              setState(() => _draft =
                                  HomeTabConfiguration(_draft.order, hidden));
                            },
                    ),
                    title: Text(tabs[i].label),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        tooltip: '上移${tabs[i].label}',
                        onPressed:
                            _saving || i == 0 ? null : () => _move(tabs[i], -1),
                        icon: const Icon(Icons.arrow_upward),
                      ),
                      IconButton(
                        tooltip: '下移${tabs[i].label}',
                        onPressed: _saving || i == tabs.length - 1
                            ? null
                            : () => _move(tabs[i], 1),
                        icon: const Icon(Icons.arrow_downward),
                      ),
                    ]),
                  ),
                ),
              if (_error != null)
                Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              TextButton(
                onPressed: _saving
                    ? null
                    : () => setState(
                        () => _draft = HomeTabConfiguration.fromStored(null)),
                child: const Text('恢复默认'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
