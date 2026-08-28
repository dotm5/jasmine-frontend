import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:jasmine/basic/log.dart';
import 'package:jasmine/basic/methods.dart';
import 'package:jasmine/configs/Authentication.dart';
import 'package:jasmine/configs/configs.dart';
import 'package:jasmine/configs/login.dart';

import '../basic/web_dav_sync.dart';
import 'app_screen.dart';
import 'components/content_loading.dart';
import 'first_login_screen.dart';
import 'network_setting_screen.dart';

class InitScreen extends StatefulWidget {
  const InitScreen({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _InitScreenState();
}

class _InitScreenState extends State<InitScreen> {
  String? _startupImagePath;
  String? _initializationError;
  bool _nativeReady = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  Widget build(BuildContext context) {
    if (_initializationError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('初始化失败')),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SelectableText(_initializationError!),
                const SizedBox(height: 16),
                const Text('请保留应用数据；原生库或存储问题修复后请重新启动应用。'),
                TextButton(onPressed: _init, child: const Text('重试')),
                if (_nativeReady)
                  TextButton(
                    onPressed:
                        () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const NetworkSettingScreen(),
                          ),
                        ),
                    child: const Text('网络设置'),
                  ),
              ],
            ),
          ),
        ),
      );
    }
    return Scaffold(
      body:
          _startupImagePath != null && _startupImagePath!.isNotEmpty
              ? Center(
                child: Image.file(
                  File(_startupImagePath!),
                  fit: BoxFit.contain,
                  width: MediaQuery.of(context).size.width,
                  height: MediaQuery.of(context).size.height,
                ),
              )
              : const ContentLoading(label: '正在准备书架…'),
    );
  }

  Future _init() async {
    if (!mounted) return;
    setState(() => _initializationError = null);
    try {
      await methods.init();
      _nativeReady = true;
      final startupImagePath = await methods.getStartupImagePath();
      if (mounted) {
        setState(() {
          _startupImagePath = startupImagePath;
        });
      }
      await methods.init2();
      if (!mounted) return;
      await initConfigs(context);
      if (!mounted) return;
      debugPrient("STATE : $loginStatus");
      await webDavSyncAuto(context);
      if (!mounted) return;
      final Widget next;
      if (currentAuthentication()) {
        next = const AuthScreen();
      } else if (loginStatus == LoginStatus.notSet) {
        next = firstLoginScreen;
      } else {
        next = const AppScreen();
      }
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => next));
    } catch (e, st) {
      debugPrient("$e\n$st");
      if (mounted) setState(() => _initializationError = '$e');
    }
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(Duration.zero, () {
      test();
    });
  }

  test() async {
    if (await verifyAuthentication(context) && mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (BuildContext context) {
            return const AppScreen();
          },
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("身份验证")),
      body: Center(
        child: Container(
          padding: const EdgeInsets.all(20),
          child: MaterialButton(
            onPressed: () async {
              test();
            },
            child: const Text('您在之前使用APP时开启了身份验证, 请点这段文字进行身份核查, 核查通过后将会进入APP'),
          ),
        ),
      ),
    );
  }
}
