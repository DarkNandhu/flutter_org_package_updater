import 'dart:convert';
import 'dart:io';
import 'package:yaml/yaml.dart';
import 'package:http/http.dart' as http;
import 'package:yaml_edit/yaml_edit.dart';
import 'package:process_run/shell.dart';

String GITHUB_TOKEN = '';
Future<void> loadGithubToken(List<String> arguments) async {
  if (arguments.isNotEmpty) {
    GITHUB_TOKEN = arguments[0];
  } else {
    final File tokenFile = File('github_token.txt');
    if (await tokenFile.exists()) {
      GITHUB_TOKEN = await tokenFile.readAsString();
    } else {
      print('GitHub token not provided and github_token.txt not found.');
      return;
    }
  }
}

void main(List<String> arguments) async {
  await loadGithubToken(arguments);
  final File file = File('pubspec.yaml');
  final String text = await file.readAsString();
  final dynamic yaml = loadYaml(text) as Map;
  final YamlEditor editor = YamlEditor(text);
  Map<String, dynamic> dependencies = jsonify(yaml['dependencies']);
  Map<String, dynamic> dependenciesOverrides =
      jsonify(yaml['dependency_overrides']);

  for (var entry in dependencies.entries) {
    await processXseedDependency(
        entry.key, entry.value, editor, 'dependencies');
  }
  for (var entry in dependenciesOverrides.entries) {
    await processXseedDependency(
        entry.key, entry.value, editor, 'dependency_overrides');
  }
  await file.writeAsString(editor.toString());

  try {
    final File pubLock = File('pubspec.lock');

    pubLock.deleteSync();
  } catch (e) {
    print(e);
  }

  var shell = Shell();
  await shell.run('flutter pub get');
}

Map<String, dynamic> jsonify(dynamic value) {
  return value is String ? jsonDecode(value) : jsonDecode(jsonEncode(value));
}

Future<void> processXseedDependency(
    String key, dynamic value, YamlEditor editor, String root) async {
  if (isXseedDependency(key)) {
    final xseedPackage = jsonify(value);
    if (isProdPackage(xseedPackage)) {
      final latestTag = await getLatestTag(xseedPackage['git']['url']);
      if (latestTag != null && latestTag != xseedPackage['git']['version']) {
        editor.update([root, key, 'git', 'version'], latestTag);
      }
    }
  }
}

Future<String?> getLatestTag(String repoUrl) async {
  final repoName = repoUrl.split('/').last.split('.').first;
  final apiUrl = 'https://api.github.com/repos/xseededucation/$repoName/tags';
  final headers = {
    'Authorization': 'Bearer $GITHUB_TOKEN',
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

bool isXseedDependency(String key) {
  return key.contains('xseed');
}
