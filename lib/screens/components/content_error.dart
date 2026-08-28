import 'package:flutter/material.dart';
import 'package:jasmine/basic/log.dart';
import 'content_state.dart';
import 'error_types.dart';

class ContentError extends StatefulWidget {
  final Object? error;
  final StackTrace? stackTrace;
  final Future<void> Function() onRefresh;

  const ContentError({
    super.key,
    required this.error,
    required this.stackTrace,
    required this.onRefresh,
  });

  @override
  State<ContentError> createState() => _ContentErrorState();
}

class _ContentErrorState extends State<ContentError> {
  bool _refreshing = false;
  bool _showDetails = false;
  Object? _retryError;

  @override
  void initState() {
    super.initState();
    _logError();
  }

  @override
  void didUpdateWidget(covariant ContentError oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.error != widget.error) {
      _retryError = null;
      _logError();
    }
  }

  void _logError() {
    debugPrient('${widget.error}');
    debugPrient('${widget.stackTrace}');
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      await widget.onRefresh();
    } catch (error, stackTrace) {
      debugPrient('$error\n$stackTrace');
      if (mounted) setState(() => _retryError = error);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _retryError ?? widget.error;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final (title, description, icon) = switch (errorType('$error')) {
      ERROR_TYPE_NETWORK => (
        '网络连接失败',
        '请检查网络连接，或在设置中切换内容与图片线路。',
        Icons.wifi_off_rounded,
      ),
      ERROR_TYPE_PERMISSION => (
        '访问受限',
        '请检查文件访问权限，以及所选目录是否仍可用。',
        Icons.folder_off_outlined,
      ),
      ERROR_TYPE_TIME => (
        '设备时间异常',
        '请开启系统自动日期与时间，然后重试。',
        Icons.schedule_outlined,
      ),
      ERROR_TYPE_UNDER_REVIEW => (
        '内容暂不可用',
        '该内容可能尚未审核或已下架，请稍后再试。',
        Icons.hide_source_outlined,
      ),
      _ => ('加载失败', '请稍后重试；如问题持续，可展开错误详情查看原因。', Icons.error_outline),
    };
    return ContentStateLayout(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 36, color: scheme.onSecondaryContainer),
          ),
          const SizedBox(height: 20),
          Text(title, textAlign: TextAlign.center, style: textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            description,
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _refreshing ? null : _refresh,
            icon:
                _refreshing
                    ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Icon(Icons.refresh),
            label: Text(_refreshing ? '重试中…' : '重新加载'),
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => setState(() => _showDetails = !_showDetails),
              icon: Icon(_showDetails ? Icons.expand_less : Icons.expand_more),
              label: Text(_showDetails ? '收起错误详情' : '查看错误详情'),
            ),
            if (_showDetails)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SelectableText('$error', style: textTheme.bodySmall),
              ),
          ],
        ],
      ),
    );
  }
}
