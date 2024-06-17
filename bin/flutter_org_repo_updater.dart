import 'dart:convert';
import 'dart:io';
import 'package:yaml/yaml.dart';
import 'package:http/http.dart' as http;
import 'package:yaml_edit/yaml_edit.dart';
import 'package:process_run/shell.dart';

Future<void> main(List<String> arguments) async {
  final config = await loadConfig();
  final orgPrefix = config['org_prefix'];
  final orgUrl = config['org_url'];
  final githubToken = config['github_token'];

  if (orgPrefix == null && orgUrl == null) {
    print('Either org_prefix or org_url must be provided in config.txt.');
    return;
  }

  if (githubToken == null) {
    print('github_token is not provided in config.txt.');
    return;
  }

  await updateDependencies(orgPrefix, orgUrl, githubToken);
}

Future<Map<String, String>> loadConfig() async {
  final File configFile = File('flutter_org_repo_updater_config.txt');
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
    print('config.txt not found.');
    return {};
  }
}

Future<void> runFlutterPubGet() async {
  var shell = Shell();
  await shell.run('flutter pub get');
}

Future<void> updateDependencies(
    String? orgPrefix, String? orgUrl, String githubToken) async {
  final File file = File('pubspec.yaml');
  final String text = await file.readAsString();
  final dynamic yaml = loadYaml(text) as Map;
  final YamlEditor editor = YamlEditor(text);
  Map<String, dynamic> dependencies = jsonify(yaml['dependencies']);
  Map<String, dynamic> dependenciesOverrides =
      jsonify(yaml['dependency_overrides']);

  for (var entry in dependencies.entries) {
    await processDependency(entry.key, entry.value, editor, 'dependencies',
        orgPrefix, orgUrl, githubToken);
  }
  for (var entry in dependenciesOverrides.entries) {
    await processDependency(entry.key, entry.value, editor,
        'dependency_overrides', orgPrefix, orgUrl, githubToken);
  }
  await file.writeAsString(editor.toString());

  try {
    final File pubLock = File('pubspec.lock');
    pubLock.deleteSync();
  } catch (e) {
    print(e);
  }

  await runFlutterPubGet();
}

Map<String, dynamic> jsonify(dynamic value) {
  return value is String ? jsonDecode(value) : jsonDecode(jsonEncode(value));
}

Future<void> processDependency(String key, dynamic value, YamlEditor editor,
    String root, String? orgPrefix, String? orgUrl, String githubToken) async {
  if (isRelevantDependency(key, value, orgPrefix, orgUrl)) {
    final package = jsonify(value);
    if (isProdPackage(package)) {
      final latestTag = await getLatestTag(package['git']['url'], githubToken);
      if (latestTag != null && latestTag != package['git']['version']) {
        editor.update([root, key, 'git', 'version'], latestTag);
      }
    }
  }
}

bool isRelevantDependency(
    String key, dynamic value, String? orgPrefix, String? orgUrl) {
  final gitUrl = value['git']?['url'] ?? '';
  return (orgPrefix != null && key.contains(orgPrefix)) ||
      (orgUrl != null && gitUrl.contains(orgUrl));
}

Future<String?> getLatestTag(String repoUrl, String githubToken) async {
  final repoName = repoUrl.split('/').last.split('.').first;
  final apiUrl = 'https://api.github.com/repos/$repoName/tags';
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

bool isProdPackage(Map<String, dynamic> json) {
  return json['git']?['version'] != null;
}
