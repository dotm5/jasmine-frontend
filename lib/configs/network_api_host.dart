import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:jasmine/basic/methods.dart';
import 'package:jasmine/basic/commons.dart' show defaultToast;

import 'network_endpoint_settings.dart';
import 'network_host.dart';

late String _apiHost;

const _defaultApiHost = 'www.cdnbtd.cc';
const _base64List = [
  "d3d3LmNkbmJlYS5uZXQ=",
  "d3d3LmNkbmh0aC5uZXQ=",
  "d3d3LmNkbmd3Yy5jYw==",
  "d3d3LmNkbmh0aC5jbHVi",
];

const _additionalFallbackApiHosts = <String>[
  'www.cdnutc.cc',
  'www.cdngwc.net',
  'www.cdngwc.club',
];

var _apiList = <String>[];

Future<void> initApiHost() async {
  _apiList = <String>[];
  _mergeApiList(<Object?>[
    _defaultApiHost,
    ..._base64List.map((e) => utf8.decode(base64.decode(e))),
    ..._additionalFallbackApiHosts,
  ]);
  try {
    final config = await methods.appConfig();
    final hosts = config['apiHosts'];
    if (hosts is Iterable) {
      _mergeApiList(hosts.cast<Object?>());
    }
  } catch (_) {
    // The local fallback remains usable when capability discovery is absent.
  }
  final rawLoaded = await methods.loadApiHost();
  _apiHost = normalizeApiHostCandidate(rawLoaded, fallback: _defaultApiHost);
  _mergeApiList(<Object?>[_apiHost]);
  if (rawLoaded.trim() != _apiHost) {
    await methods.saveApiHost(_apiHost);
  }
}

String get currentApiHostName => (_apiHost);

String normalizeApiHostCandidate(Object? raw, {String fallback = ''}) {
  return normalizeNetworkHostCandidate(raw, fallback: fallback);
}

void _mergeApiList(Iterable<Object?> items) {
  _apiList = mergeNetworkHostCandidates(<Object?>[..._apiList, ...items]);
}

class ApiOptionRow extends StatefulWidget {
  final String value;

  const ApiOptionRow(this.value, {Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _ApiOptionRowState();
}

class _ApiOptionRowState extends State<ApiOptionRow> {
  late Future<int> _feature;

  @override
  void initState() {
    super.initState();
    _feature = methods.ping(widget.value);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Expanded(child: Text(widget.value)),
        const SizedBox(width: 12),
        FutureBuilder(
          future: _feature,
          builder: (BuildContext context, AsyncSnapshot<int> snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const PingStatus("测速中", Colors.blue);
            }
            if (snapshot.hasError) {
              return const PingStatus("失败", Colors.red);
            }
            int ping = snapshot.requireData;
            if (ping <= 200) {
              return PingStatus("${ping}ms", Colors.green);
            }
            if (ping <= 500) {
              return PingStatus("${ping}ms", Colors.amber.shade800);
            }
            return PingStatus("${ping}ms", Colors.orange);
          },
        ),
      ],
    );
  }
}

class PingStatus extends StatelessWidget {
  final String title;
  final Color color;

  const PingStatus(this.title, this.color, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('\u2022', style: TextStyle(color: color)),
        Text(" $title"),
      ],
    );
  }
}

Future<void> chooseApiHost(BuildContext context) async {
  final choose = await chooseNetworkEndpoint(
    context,
    kind: EndpointKind.api,
    title: '内容线路',
    selected: _apiHost,
    fallback: _apiList,
    row: (host) => ApiOptionRow(host, key: ValueKey(host)),
  );
  if (choose == null || !context.mounted) return;
  try {
    await methods.saveApiHost(choose);
    _apiHost = await methods.loadApiHost();
    _mergeApiList(<Object?>[_apiHost]);
  } catch (error) {
    if (context.mounted) defaultToast(context, '$error');
  }
}

Widget apiHostSetting() {
  return StatefulBuilder(
    builder: (BuildContext context, void Function(void Function()) setState) {
      return ListTile(
        onTap: () async {
          await chooseApiHost(context);
          if (context.mounted) setState(() {});
        },
        title: const Text("内容线路"),
        trailing: const Icon(Icons.chevron_right),
        subtitle: Text(_apiHost),
      );
    },
  );
}
