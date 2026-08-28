import 'package:flutter/material.dart';
import 'package:jasmine/basic/commons.dart';
import 'package:jasmine/configs/login.dart';
import 'package:jasmine/screens/about_screen.dart';
import 'package:jasmine/screens/comments_screen.dart';
import 'package:jasmine/screens/components/avatar.dart';
import 'package:jasmine/screens/local_build_screen.dart';
import 'package:jasmine/screens/components/recommend_links_panel.dart';
import 'package:jasmine/screens/settings_screen.dart';
import 'package:jasmine/screens/view_log_screen.dart';

import '../basic/platform.dart';
import '../configs/daily_sign.dart';
import '../configs/is_pro.dart';
import 'components/badge.dart';
import 'components/expressive_action_card.dart';
import 'downloads_screen.dart';
import 'favorites_screen.dart';

class UserScreen extends StatefulWidget {
  const UserScreen({super.key});

  @override
  State<UserScreen> createState() => _UserScreenState();
}

class _UserScreenState extends State<UserScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    loginEvent.subscribe(_setState);
    proEvent.subscribe(_setState);
    dailySignEvent.subscribe(_setState);
  }

  @override
  void dispose() {
    loginEvent.unsubscribe(_setState);
    proEvent.unsubscribe(_setState);
    dailySignEvent.unsubscribe(_setState);
    super.dispose();
  }

  void _setState(_) {
    if (mounted) setState(() {});
  }

  void _open(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('书架'),
        actions: [
          IconButton(
            tooltip: '功能与说明',
            onPressed: () => _open(const LocalBuildScreen()),
            icon: const Icon(Icons.help_outline),
          ),
          IconButton(
            tooltip: '设置',
            onPressed: () => _open(const SettingsScreen()),
            icon: const Icon(Icons.settings_outlined),
          ),
          if (normalPlatform)
            IconButton(
              tooltip: '关于 Jasmine',
              onPressed: () => _open(const AboutScreen()),
              icon: const VersionBadged(
                child: Padding(
                  padding: EdgeInsets.all(1),
                  child: Icon(Icons.info_outlined),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 840;
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: ListView(
                  padding: EdgeInsets.all(wide ? 24 : 16),
                  children: [
                    if (wide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(width: 320, child: _buildAccountCard()),
                          const SizedBox(width: 24),
                          Expanded(child: _buildReadingEntries()),
                        ],
                      )
                    else ...[
                      _buildAccountCard(),
                      const SizedBox(height: 24),
                      _buildReadingEntries(),
                    ],
                    const SizedBox(height: 24),
                    const RecommendLinksPanel(padding: EdgeInsets.zero),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildReadingEntries() {
    final entries = [
      ExpressiveActionCard(
        icon: Icons.bookmarks_rounded,
        title: '收藏夹',
        subtitle: '整理收藏，管理文件夹',
        onTap: () {
          if (loginStatus == LoginStatus.loginSuccess) {
            _open(const FavoritesScreen());
          } else {
            defaultToast(context, '登录后即可使用收藏夹');
          }
        },
      ),
      ExpressiveActionCard(
        icon: Icons.history_rounded,
        title: '浏览历史',
        subtitle: '找回最近浏览的漫画',
        onTap: () => _open(const ViewLogScreen()),
      ),
      ExpressiveActionCard(
        icon: Icons.download_rounded,
        title: '下载管理',
        subtitle: '查看进度，阅读已下载内容',
        secondary: true,
        onTap: () => _open(const DownloadsScreen()),
      ),
      ExpressiveActionCard(
        icon: Icons.forum_rounded,
        title: '讨论区',
        subtitle: '浏览留言，参与交流',
        secondary: true,
        onTap: () => _open(const CommentsScreen()),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 16),
          child: Text(
            '我的阅读',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        for (var i = 0; i < entries.length; i++) ...[
          entries[i],
          if (i != entries.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _buildAccountCard() {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme.apply(
      bodyColor: scheme.onPrimaryContainer,
      displayColor: scheme.onPrimaryContainer,
    );
    Widget child;
    switch (loginStatus) {
      case LoginStatus.notSet:
        child = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.account_circle_outlined,
              size: 48,
              color: scheme.onPrimaryContainer,
            ),
            const SizedBox(height: 12),
            Text(
              '让喜欢的漫画有个归处',
              textAlign: TextAlign.center,
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '登录后可管理收藏夹和每日签到',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => loginDialog(context),
              icon: const Icon(Icons.login),
              label: const Text('登录 / 注册'),
            ),
          ],
        );
        break;
      case LoginStatus.logging:
        child = const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 32,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            SizedBox(height: 16),
            Text('正在登录…'),
          ],
        );
        break;
      case LoginStatus.loginSuccess:
        child = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Avatar(selfInfo.photo),
            const SizedBox(height: 12),
            Text(
              selfInfo.username,
              textAlign: TextAlign.center,
              style: textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: scheme.onPrimaryContainer,
                side: BorderSide(color: scheme.onPrimaryContainer),
              ),
              onPressed:
                  dailySignStatus == DailySignStatus.checking
                      ? null
                      : () => checkDailySignStatus(context, toast: true),
              icon: Icon(
                dailySignStatus == DailySignStatus.signed
                    ? Icons.check_circle_outline
                    : Icons.event_available_outlined,
              ),
              label: Text(dailySignStatusLabel()),
            ),
          ],
        );
        break;
      case LoginStatus.loginField:
        child = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_off_outlined, size: 40, color: scheme.error),
            const SizedBox(height: 12),
            Text('登录未完成', style: textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text('请检查网络或账号信息后重试', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => loginDialog(context),
              child: const Text('重新登录'),
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: scheme.onPrimaryContainer,
              ),
              onPressed:
                  () => showDialog<void>(
                    context: context,
                    builder:
                        (context) => AlertDialog(
                          title: const Text('登录错误详情'),
                          content: SingleChildScrollView(
                            child: SelectableText(loginMessage),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('关闭'),
                            ),
                          ],
                        ),
                  ),
              child: const Text('查看错误详情'),
            ),
          ],
        );
        break;
    }
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        child: DefaultTextStyle(style: textTheme.bodyMedium!, child: child),
      ),
    );
  }
}
