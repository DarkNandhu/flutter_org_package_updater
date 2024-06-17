import 'dart:convert';
import 'dart:io';
import 'package:yaml/yaml.dart';
import 'package:http/http.dart' as http;
import 'package:yaml_edit/yaml_edit.dart';
import 'package:process_run/shell.dart';

class FlutterOrgRepoUpdater {
  final String configFilePath;
  late Map<String, String> config;

  FlutterOrgRepoUpdater({required this.configFilePath});

  Future<void> run() async {
    config = await _loadConfig();
    final orgPrefix = config['org_prefix'];
    final orgUrl = config['org_url'];
    final githubToken = config['github_token'];
    final ownerName = config['owner_name'];

    if ((orgPrefix == null || orgPrefix.isEmpty) &&
        (orgUrl == null || orgUrl.isEmpty)) {
      print(
          'Either org_prefix or org_url must be provided in $configFilePath.');
      return;
    }

    if (githubToken == null || githubToken.isEmpty) {
      print('github_token is not provided in $configFilePath.');
      return;
    }

    await _updateDependencies(
      orgPrefix: orgPrefix,
      orgUrl: orgUrl,
      githubToken: githubToken,
      ownerName: ownerName,
    );
  }

  Future<Map<String, String>> _loadConfig() async {
    final File configFile = File(configFilePath);
    if (await configFile.exists()) {
      final lines = await configFile.readAsLines();
      final config = <String, String>{};
      for (var line in lines) {
        final parts = line.split('=');
        if (parts.length == 2) {
          config[parts[0].trim()] = parts[1].trim();
        }
      }
      return config;
    } else {
      print('$configFilePath not found.');
      return {};
    }
  }

  Future<void> _runFlutterPubGet() async {
    var shell = Shell();
    await shell.run('flutter pub get');
  }

  Future<void> _updateDependencies({
    String? orgPrefix,
    String? orgUrl,
    required String githubToken,
    String? ownerName,
  }) async {
    final File file = File('pubspec.yaml');
    final String text = await file.readAsString();
    final dynamic yaml = loadYaml(text) as Map;
    final YamlEditor editor = YamlEditor(text);
    final Map<String, dynamic> dependencies = _jsonify(yaml['dependencies']);
    final Map<String, dynamic> dependenciesOverrides =
        _jsonify(yaml['dependency_overrides']);

    for (var entry in dependencies.entries) {
      await _processDependency(
        key: entry.key,
        value: entry.value,
        editor: editor,
        root: 'dependencies',
        orgPrefix: orgPrefix,
        orgUrl: orgUrl,
        githubToken: githubToken,
        ownerName: ownerName,
      );
    }
    for (var entry in dependenciesOverrides.entries) {
      await _processDependency(
        key: entry.key,
        value: entry.value,
        editor: editor,
        root: 'dependency_overrides',
        orgPrefix: orgPrefix,
        orgUrl: orgUrl,
        githubToken: githubToken,
        ownerName: ownerName,
      );
    }
    await file.writeAsString(editor.toString());

    try {
      final File pubLock = File('pubspec.lock');
      pubLock.deleteSync();
    } catch (e) {
      print(e);
    }

    await _runFlutterPubGet();
  }

  Map<String, dynamic> _jsonify(dynamic value) {
    return value is String ? jsonDecode(value) : jsonDecode(jsonEncode(value));
  }

  Future<void> _processDependency({
    required String key,
    required dynamic value,
    required YamlEditor editor,
    required String root,
    String? orgPrefix,
    String? orgUrl,
    required String githubToken,
    String? ownerName,
  }) async {
    if (_isRelevantDependency(
      key: key,
      value: value,
      orgPrefix: orgPrefix,
      orgUrl: orgUrl,
    )) {
      final package = _jsonify(value);
      if (_isProdPackage(package)) {
        final latestTag = await _getLatestTag(
          repoUrl: package['git']['url'],
          githubToken: githubToken,
          ownerName: ownerName,
        );
        if (latestTag != null && latestTag != package['git']['version']) {
          editor.update([root, key, 'git', 'version'], latestTag);
        }
      }
    }
  }

  bool _isRelevantDependency({
    required String key,
    required dynamic value,
    String? orgPrefix,
    String? orgUrl,
  }) {
    final gitUrl =
        value is Map && value.containsKey('git') && value['git'] is Map
            ? value['git']['url'] ?? ''
            : '';
    return (orgPrefix != null && key.contains(orgPrefix)) ||
        (orgUrl != null && gitUrl.contains(orgUrl));
  }

  Future<String?> _getLatestTag({
    required String repoUrl,
    required String githubToken,
    String? ownerName,
  }) async {
    final repoName = repoUrl.split('/').last.split('.').first;
    final apiUrl = ownerName != null && ownerName.isNotEmpty
        ? 'https://api.github.com/repos/$ownerName/$repoName/tags'
        : 'https://api.github.com/repos/$repoName/tags';
    final headers = {
      'Authorization': 'Bearer $githubToken',
      'Accept': 'application/vnd.github.v3+json',
      'X-GitHub-Api-Version': '2022-11-28',
    };

    final response = await http.get(Uri.parse(apiUrl), headers: headers);
    if (response.statusCode == 200) {
      final tags = jsonDecode(response.body) as List;
      return tags.isNotEmpty ? tags.first['name'] as String? : null;
    } else {
      print('Failed to fetch tags for $repoUrl: ${response.reasonPhrase}');
    }
    return null;
  }

  bool _isProdPackage(Map<String, dynamic> json) {
    return json['git']?['version'] != null;
  }
}

Future<void> main(List<String> arguments) async {
  final updater = FlutterOrgRepoUpdater(
      configFilePath: 'flutter_org_repo_updater_config.txt');
  await updater.run();
}
