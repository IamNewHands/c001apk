import 'package:flutter/material.dart';

import '../logic/content_filter/app_content_filter.dart';
import '../logic/content_filter/content_filter_projection.dart';
import '../logic/content_filter/content_filter_rule.dart';
import '../logic/model/feed/datum.dart';
import '../utils/storage_util.dart';

class ContentFilterRevealScope extends InheritedWidget {
  const ContentFilterRevealScope(
      {super.key,
      required super.child,
      this.contentKeys = const {},
      this.authorUids = const {}});
  final Set<String> contentKeys;
  final Set<String> authorUids;
  static ContentFilterRevealScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ContentFilterRevealScope>();
  @override
  bool updateShouldNotify(ContentFilterRevealScope oldWidget) => true;
}

/// Does not construct hidden content, including images and interactive targets.
class ContentFilterGate extends StatefulWidget {
  const ContentFilterGate(
      {super.key,
      required this.data,
      required this.builder,
      this.scope,
      this.hiddenChildren,
      this.page = false,
      this.onReveal,
      this.onClose});
  final Datum data;
  final WidgetBuilder builder;
  final FilterScope? scope;
  final WidgetBuilder? hiddenChildren;
  final bool page;
  final VoidCallback? onReveal;
  final VoidCallback? onClose;
  @override
  State<ContentFilterGate> createState() => _ContentFilterGateState();
}

class _ContentFilterGateState extends State<ContentFilterGate> {
  bool _revealed = false;
  @override
  void didUpdateWidget(ContentFilterGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (ContentFilterProjection.keyOf(oldWidget.data, scope: oldWidget.scope) !=
        ContentFilterProjection.keyOf(widget.data, scope: widget.scope)) {
      _revealed = false;
    }
  }

  Widget _build(BuildContext context) {
    final key = ContentFilterProjection.keyOf(widget.data, scope: widget.scope);
    final local = ContentFilterRevealScope.of(context);
    final hit = ContentFilterProjection.match(widget.data, scope: widget.scope);
    final allowed = local?.contentKeys.contains(key) == true ||
        (hit?.kind == FilterRuleKind.author &&
            local?.authorUids.contains('${widget.data.uid}') == true);
    if (_revealed || allowed || hit == null) return widget.builder(context);
    final placeholder = Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('已过滤：${hit.reason}',
                style: Theme.of(context).textTheme.bodyMedium),
            Wrap(spacing: 8, children: [
              TextButton(
                  onPressed: () {
                    setState(() => _revealed = true);
                    widget.onReveal?.call();
                  },
                  child: const Text('仅本次查看')),
              TextButton(
                  onPressed: () async {
                    await disableContentFilterRule(hit);
                    if (mounted) setState(() {});
                  },
                  child: Text(
                      hit.ruleId.startsWith('legacy.') ? '移出个人黑名单' : '停用此规则')),
            ]),
            if (widget.hiddenChildren != null) widget.hiddenChildren!(context),
          ]),
    );
    if (!widget.page) return placeholder;
    return Scaffold(
        appBar: AppBar(
            title: const Text('内容已过滤'),
            leading: BackButton(onPressed: widget.onClose)),
        body: SingleChildScrollView(child: placeholder));
  }

  @override
  Widget build(BuildContext context) {
    final service = AppContentFilter.service;
    return service == null
        ? _build(context)
        : ListenableBuilder(
            listenable: service, builder: (context, _) => _build(context));
  }
}

Future<void> disableContentFilterRule(FilterMatch match) async {
  if (match.ruleId.startsWith('legacy.user:')) {
    GStorage.onBlock(match.ruleId.substring('legacy.user:'.length),
        isDelete: true);
  } else if (match.ruleId.startsWith('legacy.topic:')) {
    GStorage.onBlock(match.ruleId.substring('legacy.topic:'.length),
        isUser: false, isDelete: true);
  } else {
    await AppContentFilter.service?.setRuleDisabled(match.ruleId, true);
  }
}
