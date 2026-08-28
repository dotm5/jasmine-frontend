import 'package:flutter/material.dart';

class LocalBuildScreen extends StatelessWidget {
  const LocalBuildScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('功能与说明')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Icon(
                  Icons.auto_stories_outlined,
                  size: 48,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  '把阅读留给自己',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  '发现、收藏与阅读，在 Jasmine 里继续。',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 28),
                const _FeatureCard(
                  Icons.explore_outlined,
                  '发现与阅读',
                  '浏览分类和排行，搜索漫画，按章节阅读。',
                ),
                const _FeatureCard(
                  Icons.bookmarks_outlined,
                  '管理书架',
                  '登录后管理收藏夹；在浏览历史中找回看过的内容。',
                ),
                const _FeatureCard(
                  Icons.download_outlined,
                  '下载与导出',
                  '保存漫画以便离线阅读，也可将已下载内容导出。',
                ),
                const _FeatureCard(
                  Icons.sync_outlined,
                  '同步与个性化',
                  '配置 WebDAV 同步，按习惯调整主题、字号和阅读方式。',
                ),
                const SizedBox(height: 16),
                Card(
                  child: ExpansionTile(
                    leading: const Icon(Icons.info_outline),
                    title: const Text('使用提示'),
                    childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    children: const [
                      Text(
                        '收藏和签到需要登录。遇到列表或详情加载失败时，可尝试切换内容线路；封面或正文图片加载失败时，可尝试切换图片线路。\n\n线路测速仅供参考，不代表所有内容均可访问。同步前请先确认 WebDAV 配置，并保留重要数据的备份。',
                      ),
                    ],
                  ),
                ),
                Card(
                  child: ExpansionTile(
                    leading: const Icon(Icons.code),
                    title: const Text('开源致谢'),
                    childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    children: const [
                      Text(
                        '界面基于 Jasmine，原生后端源自 Jenny；网络协议、图片处理和 PDF 实现参考 jmcomic-downloader。感谢这些开源项目的贡献。\n\n本版本的本地功能独立于原作者的会员服务，不展示或兑换会员资格。',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  const _FeatureCard(this.icon, this.title, this.description);

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(title),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(description),
      ),
    ),
  );
}
