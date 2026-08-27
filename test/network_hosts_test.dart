import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jasmine/configs/network_host.dart';

void main() {
  test('normalizes URL-like host values and JSON wrappers', () {
    expect(
      normalizeNetworkHostCandidate(
        ' https://user:pass@API.example.com:8443/path ',
      ),
      'API.example.com:8443',
    );
    expect(
      normalizeNetworkHostCandidate(jsonEncode(' //cdn.example.com/a ')),
      'cdn.example.com',
    );
    expect(
      normalizeNetworkHostCandidate(' ', fallback: 'fallback.example'),
      'fallback.example',
    );
    expect(
      normalizeNetworkHostCandidate('http://127.0.0.1:3000/path'),
      'http://127.0.0.1:3000',
    );
  });

  test('splits explicit host lists without splitting query commas', () {
    expect(
      normalizeNetworkHostCandidateList(
        jsonEncode(
          ' https://cdn-a.example.com/a, //cdn-b.example.com:9443/b\nCDN-A.example.com ',
        ),
      ),
      ['cdn-a.example.com', 'cdn-b.example.com:9443'],
    );
    expect(
      normalizeNetworkHostCandidateList(
        'https://cdn-query.example.com/path?mirror=bad-a.example.com,bad-b.example.com; cdn-ok.example.com',
      ),
      ['cdn-query.example.com', 'cdn-ok.example.com'],
    );
    expect(
      normalizeNetworkHostCandidateList(
        'http://127.0.0.1:3000/a, localhost:4000; [::1]:9443, //[2001:db8::1]:9443/path',
      ),
      [
        'http://127.0.0.1:3000',
        'localhost:4000',
        '[::1]:9443',
        '[2001:db8::1]:9443',
      ],
    );
  });

  test('merges candidates stably and case-insensitively', () {
    expect(
      mergeNetworkHostCandidates(<Object?>[
        'https://first.example/a',
        'FIRST.example',
        'second.example; third.example',
        'https://SECOND.example/path',
      ]),
      ['first.example', 'second.example', 'third.example'],
    );
  });

  test('keeps a selected custom host when backend candidates are merged', () {
    final selected = normalizeNetworkHostCandidate(
      'https://user:pass@selected.example:9443/path',
    );
    expect(
      mergeNetworkHostCandidates(<Object?>[
        'default.example',
        'backend.example',
        selected,
      ]),
      ['default.example', 'backend.example', 'selected.example:9443'],
    );
  });
}
