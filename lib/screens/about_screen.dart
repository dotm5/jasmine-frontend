import 'package:flutter/material.dart';
import 'package:jasmine/basic/commons.dart';
import 'package:jasmine/configs/versions.dart';
import 'package:jasmine/screens/components/badge.dart';
import 'components/right_click_pop.dart';
import 'local_build_screen.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = latestVersionInfo();
    return rightClickPop(
      context: context,
      child: Scaffold(
        appBar: AppBar(title: const Text('关于')),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const SizedBox(height: 20),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Icon(
                        Icons.auto_stories_outlined,
                        size: 56,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Jasmine',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '发现喜欢的，接着上次读。',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Card(
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.verified_outlined),
                          title: const Text('当前版本'),
                          subtitle: Text(currentVersion()),
                        ),
                        const Divider(height: 1, indent: 56),
                        ListTile(
                          leading: const VersionBadged(
                            child: Icon(Icons.update),
                          ),
                          title: const Text('更新信息'),
                          subtitle: Text(latestVersion ?? '暂未获取更新信息'),
                        ),
                        if (latestVersion != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            child: OutlinedButton.icon(
                              onPressed: () => openUrl(latestDownloadUrl()),
                              icon: const Icon(Icons.open_in_new),
                              label: const Text('前往下载页面'),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.help_outline),
                      title: const Text('功能与说明'),
                      subtitle: const Text('使用提示与开源致谢'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap:
                          () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const LocalBuildScreen(),
                            ),
                          ),
                    ),
                  ),
                  if (info != null && info.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text('更新内容', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 12),
                    SelectableText(info),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
