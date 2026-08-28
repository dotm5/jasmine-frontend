import 'package:flutter/material.dart';
import '../../basic/platform.dart';
import '../../configs/daily_sign.dart';
import '../../configs/login.dart';
import '../about_screen.dart';
import '../comments_screen.dart';
import '../local_build_screen.dart';
import '../settings_screen.dart';
import 'avatar.dart';
import 'badge.dart';
import 'expressive_page_transitions.dart';
import 'recommend_links_panel.dart';

class ReadingAccountButton extends StatelessWidget {
  const ReadingAccountButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: '账户与设置',
    onPressed:
        () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          useSafeArea: true,
          builder: (_) => const _ReadingAccountSheet(),
        ),
    icon: VersionBadged(
      child:
          loginStatus == LoginStatus.loginSuccess && selfInfo.photo.isNotEmpty
              ? Avatar(selfInfo.photo, size: 26)
              : const Icon(Icons.account_circle_outlined, size: 32),
    ),
  );
}

class _ReadingAccountSheet extends StatefulWidget {
  const _ReadingAccountSheet();
  @override
  State<_ReadingAccountSheet> createState() => _ReadingAccountSheetState();
}

class _ReadingAccountSheetState extends State<_ReadingAccountSheet> {
  @override
  void initState() {
    super.initState();
    loginEvent.subscribe(_refresh);
    dailySignEvent.subscribe(_refresh);
  }

  @override
  void dispose() {
    loginEvent.unsubscribe(_refresh);
    dailySignEvent.unsubscribe(_refresh);
    super.dispose();
  }

  void _refresh(_) {
    if (mounted) setState(() {});
  }

  void _open(Widget screen) {
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(AppPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .78,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        children: [
          Text('账户与设置', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 20),
          if (loginStatus == LoginStatus.loginSuccess) ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Avatar(selfInfo.photo, size: 36),
              title: Text(selfInfo.username),
              subtitle: const Text('收藏与阅读，一起整理'),
            ),
            OutlinedButton.icon(
              onPressed:
                  dailySignStatus == DailySignStatus.checking
                      ? null
                      : () => checkDailySignStatus(context, toast: true),
              icon: const Icon(Icons.event_available_outlined),
              label: Text(dailySignStatusLabel()),
            ),
          ] else if (loginStatus == LoginStatus.logging)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            Text(
              loginStatus == LoginStatus.loginField
                  ? '登录未完成，请检查网络或账号信息'
                  : '登录后可使用收藏夹和每日签到',
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => loginDialog(context),
              icon: const Icon(Icons.login),
              label: Text(
                loginStatus == LoginStatus.loginField ? '重新登录' : '登录 / 注册',
              ),
            ),
            if (loginStatus == LoginStatus.loginField)
              TextButton(
                onPressed:
                    () => showDialog<void>(
                      context: context,
                      builder:
                          (_) => AlertDialog(
                            title: const Text('登录错误详情'),
                            content: SingleChildScrollView(
                              child: SelectableText(loginMessage),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('关闭'),
                              ),
                            ],
                          ),
                    ),
                child: const Text('查看错误详情'),
              ),
          ],
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('设置'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(const SettingsScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.forum_outlined),
            title: const Text('讨论区'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(const CommentsScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('功能与说明'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(const LocalBuildScreen()),
          ),
          if (normalPlatform)
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('关于 Jasmine'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _open(const AboutScreen()),
            ),
          const RecommendLinksPanel(padding: EdgeInsets.zero),
        ],
      ),
    );
  }
}
