
# Flutter Org Repo Updater

This Dart script updates dependencies in a Flutter project's `pubspec.yaml` by checking the latest tags for specified repositories on GitHub. It ensures that the dependencies are always up-to-date with the latest versions available.

## Features

- Automatically updates dependencies in `pubspec.yaml` with the latest tag versions from GitHub.
- Supports optional `org_prefix` and `org_url` for filtering relevant dependencies.
- Supports specifying a GitHub repository owner with `owner_name`.
- Runs `flutter pub get` after updating dependencies to refresh the project's dependency tree.

## Installation

1. **Add this repository as a dev dependency in your Flutter project:**

   ```yaml
   dev_dependencies:
     flutter_org_repo_updater:
       git:
         url: https://github.com/your_username/flutter_org_repo_updater.git
         ref: master
   ```

2. **Create a configuration file named `flutter_org_repo_updater_config.txt` in the root of your Flutter project with the following content:**

   ```plaintext
   org_prefix=xseed
   org_url=https://github.com/xseededucation
   owner_name=your_owner_name
   github_token=your_github_token
   ```

   - `org_prefix` (optional): The prefix used to filter dependencies by name.
   - `org_url` (optional): The URL used to filter dependencies by Git repository URL.
   - `owner_name` (optional): The GitHub owner name for the repositories. This is used to construct the API URL.
   - `github_token` (required): Your GitHub personal access token for authenticating API requests.

## Usage

1. **Place the script files and `flutter_org_repo_updater_config.txt` in the root of your Flutter project.**

2. **Run the script using Dart:**

   ```bash
   dart run flutter_org_repo_updater
   ```

## Script Structure

### Main Class: `FlutterOrgRepoUpdater`

The main class handles the configuration loading, dependency updating, and running the `flutter pub get` command.

#### Methods

- `run()`: The main entry point for running the updater.
- `_loadConfig()`: Loads the configuration from `flutter_org_repo_updater_config.txt`.
- `_runFlutterPubGet()`: Runs `flutter pub get` to refresh dependencies.
- `_updateDependencies()`: Updates the dependencies in `pubspec.yaml` with the latest tags from GitHub.
- `_jsonify()`: Converts a YAML value to a JSON-compatible format.
- `_processDependency()`: Processes each dependency to update it with the latest tag if relevant.
- `_isRelevantDependency()`: Checks if a dependency is relevant based on `org_prefix` or `org_url`.
- `_getLatestTag()`: Retrieves the latest tag from the GitHub repository.
- `_isProdPackage()`: Checks if a package is a production package.

