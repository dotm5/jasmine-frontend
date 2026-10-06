import 'package:flutter/material.dart';
import 'package:jasmine/basic/commons.dart';
import 'package:jasmine/basic/methods.dart';

const _propertyName = "auto_clean";
late String autoClean;
String cacheMaxBytes = '2147483648';

Map<String, String> _nameMap = {
  '0': '不按时间清理',
  (3600 * 24).toString(): "一天",
  (3600 * 24 * 7).toString(): "一周",
  (3600 * 24 * 30).toString(): "一月",
  (3600 * 24 * 30 * 12).toString(): "一年",
};
const _capacityNames = {
  '536870912': '512 MB',
  '1073741824': '1 GB',
  '2147483648': '2 GB',
  '4294967296': '4 GB',
  '8589934592': '8 GB',
  '0': '不限制容量',
};

Future initAutoClean() async {
  final capacity = await methods.loadProperty('cache_max_bytes');
  if (capacity.isNotEmpty) cacheMaxBytes = capacity;
  autoClean = await methods.loadProperty(_propertyName);
  if (autoClean.isEmpty) {
    autoClean = (3600 * 24 * 7).toString();
    await methods.saveProperty(_propertyName, autoClean);
  }
}

String autoCleanName() {
  return '缓存设置';
}

Future chooseAutoClean(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder:
        (dialogContext) => StatefulBuilder(
          builder:
              (context, setState) => AlertDialog(
                title: const Text('缓存回收设置'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        '设置保存后立即清理。运行期间自动检查，超出容量时优先删除较早缓存。离线下载与导出文件不受影响。',
                      ),
                      ListTile(
                        title: const Text('图片缓存保留时间'),
                        subtitle: Text(_nameMap[autoClean] ?? '$autoClean 秒'),
                        onTap: () async {
                          final choose = await chooseMapDialog(
                            context,
                            title: '图片缓存保留时间',
                            values: _nameMap.map((k, v) => MapEntry(v, k)),
                          );
                          if (choose == null) return;
                          try {
                            await methods.saveProperty(_propertyName, choose);
                            autoClean = choose;
                            if (context.mounted) setState(() {});
                          } catch (e) {
                            if (context.mounted) {
                              defaultToast(context, '保存或清理失败：$e');
                            }
                          }
                        },
                      ),
                      ListTile(
                        title: const Text('图片缓存容量上限'),
                        subtitle: Text(
                          _capacityNames[cacheMaxBytes] ?? '$cacheMaxBytes 字节',
                        ),
                        onTap: () async {
                          final choose = await chooseMapDialog(
                            context,
                            title: '图片缓存容量上限',
                            values: _capacityNames.map(
                              (k, v) => MapEntry(v, k),
                            ),
                          );
                          if (choose == null) return;
                          try {
                            await methods.saveProperty(
                              'cache_max_bytes',
                              choose,
                            );
                            cacheMaxBytes = choose;
                            if (context.mounted) setState(() {});
                          } catch (e) {
                            if (context.mounted) {
                              defaultToast(context, '保存或清理失败：$e');
                            }
                          }
                        },
                      ),
                      const Text(
                        '保留时间从最近使用开始计算。刚使用的图片保护一分钟，容量可能短暂超限。关闭限制后仍回收无索引文件和过期接口数据。',
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('完成'),
                  ),
                ],
              ),
        ),
  );
}
