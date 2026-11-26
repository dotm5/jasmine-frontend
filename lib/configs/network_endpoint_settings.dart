import 'package:flutter/material.dart';
import 'package:jasmine/basic/commons.dart' show defaultToast;
import 'package:jasmine/basic/methods.dart';

import 'network_host.dart';

Future<String?> chooseNetworkEndpoint(
  BuildContext context, {
  required EndpointKind kind,
  required String title,
  required String selected,
  required List<String> fallback,
  required Widget Function(String host) row,
}) {
  return showDialog<String>(
    context: context,
    builder:
        (_) => _EndpointDialog(
          kind: kind,
          title: title,
          selected: selected,
          fallback: fallback,
          row: row,
        ),
  );
}

class _EndpointDialog extends StatefulWidget {
  const _EndpointDialog({
    required this.kind,
    required this.title,
    required this.selected,
    required this.fallback,
    required this.row,
  });

  final EndpointKind kind;
  final String title;
  final String selected;
  final List<String> fallback;
  final Widget Function(String host) row;

  @override
  State<_EndpointDialog> createState() => _EndpointDialogState();
}

class _EndpointDialogState extends State<_EndpointDialog> {
  EndpointOptions? _options;
  bool _removing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final options = await methods.loadEndpointOptions(widget.kind);
      if (mounted) setState(() => _options = options);
    } catch (_) {
      // Older native builds still expose the bundled list through app_config.
    }
  }

  Future<void> _remove(String host) async {
    setState(() => _removing = true);
    try {
      await methods.removeCustomEndpoint(widget.kind, host);
      await _load();
    } catch (error) {
      if (mounted) defaultToast(context, '$error');
    } finally {
      if (mounted) setState(() => _removing = false);
    }
  }

  Future<void> _manualInput() async {
    var value = widget.selected;
    final result = await showDialog<String>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text('输入${widget.title}地址'),
            content: TextFormField(
              initialValue: value,
              onChanged: (input) => value = input,
              decoration: const InputDecoration(hintText: 'www.example.com'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, value.trim()),
                child: const Text('确定'),
              ),
            ],
          ),
    );
    if (mounted && result != null && result.isNotEmpty) {
      Navigator.pop(context, result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final custom = _options?.custom ?? const <String>[];
    final hosts = mergeNetworkHostCandidates([
      ...(_options?.official ?? widget.fallback),
      ...custom,
      widget.selected,
    ]);
    return SimpleDialog(
      title: Text(widget.title),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: Text(
            widget.kind == EndpointKind.api
                ? '测速检查内容接口。登录请求将发送至所选线路。'
                : '测速检查域名连接，图片加载以实际结果为准。',
          ),
        ),
        for (final host in hosts)
          SimpleDialogOption(
            key: ValueKey(host),
            onPressed: _removing ? null : () => Navigator.pop(context, host),
            child: Row(
              children: [
                Expanded(child: widget.row(host)),
                if (custom.contains(host) && host != widget.selected)
                  IconButton(
                    tooltip: '删除自定义线路',
                    onPressed: _removing ? null : () => _remove(host),
                    icon: const Icon(Icons.close, size: 18),
                  ),
              ],
            ),
          ),
        SimpleDialogOption(
          onPressed: _removing ? null : _manualInput,
          child: const Text('手动输入'),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ],
    );
  }
}

class RefreshEndpointsTile extends StatefulWidget {
  const RefreshEndpointsTile({super.key});

  @override
  State<RefreshEndpointsTile> createState() => _RefreshEndpointsTileState();
}

class _RefreshEndpointsTileState extends State<RefreshEndpointsTile> {
  bool _busy = false;
  String? _summary;

  String _describe(String kind, EndpointRefresh result) {
    final error = result.error;
    return error == null
        ? '$kind线路已获取 ${result.count} 条'
        : '$kind线路更新失败，使用上次列表';
  }

  Future<void> _refresh() async {
    setState(() => _busy = true);
    try {
      final result = await methods.refreshEndpoints();
      if (mounted) {
        setState(() {
          _summary = [
            _describe('内容', result.api),
            _describe('图片', result.cdn),
          ].join('\n');
        });
      }
    } catch (error) {
      if (mounted) defaultToast(context, '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListTile(
    title: const Text('更新线路列表'),
    subtitle: Text(_busy ? '正在获取内容与图片线路' : _summary ?? '获取最新内容与图片线路'),
    onTap: _busy ? null : _refresh,
    trailing:
        _busy
            ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
            : const Icon(Icons.sync),
  );
}
