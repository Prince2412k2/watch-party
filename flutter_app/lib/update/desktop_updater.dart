import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../app/desktop_lifecycle.dart';
import '../data/api_client.dart';
import '../state/providers.dart';

enum UpdateStatus {
  loading,
  idle,
  checking,
  upToDate,
  available,
  downloading,
  manualInstall,
  error,
}

class ReleaseArtifact {
  const ReleaseArtifact({
    required this.filename,
    required this.url,
    required this.size,
    required this.sha256,
  });

  factory ReleaseArtifact.fromJson(Map<String, dynamic> json) {
    final filename = json['filename'];
    final url = json['url'];
    final size = json['size'];
    final hash = json['sha256'];
    if (filename is! String ||
        filename.isEmpty ||
        filename == '.' ||
        filename == '..' ||
        filename.contains('/') ||
        filename.contains(r'\') ||
        url is! String ||
        size is! int ||
        size < 1 ||
        hash is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) {
      throw const FormatException('Invalid release artifact');
    }
    return ReleaseArtifact(
      filename: filename,
      url: url,
      size: size,
      sha256: hash,
    );
  }

  final String filename;
  final String url;
  final int size;
  final String sha256;
}

class DesktopRelease {
  const DesktopRelease({
    required this.version,
    required this.build,
    required this.commit,
    required this.builtAt,
    required this.artifacts,
  });

  factory DesktopRelease.fromJson(Map<String, dynamic> json) {
    final version = json['version'];
    final build = json['build'];
    final commit = json['commit'];
    final builtAt = DateTime.tryParse(json['builtAt']?.toString() ?? '');
    final rawArtifacts = json['artifacts'];
    if (version is! String ||
        build is! int ||
        build < 1 ||
        commit is! String ||
        builtAt == null ||
        rawArtifacts is! Map) {
      throw const FormatException('Invalid release metadata');
    }
    return DesktopRelease(
      version: version,
      build: build,
      commit: commit,
      builtAt: builtAt,
      artifacts: rawArtifacts.map(
        (key, value) => MapEntry(
          key.toString(),
          ReleaseArtifact.fromJson(Map<String, dynamic>.from(value as Map)),
        ),
      ),
    );
  }

  final String version;
  final int build;
  final String commit;
  final DateTime builtAt;
  final Map<String, ReleaseArtifact> artifacts;
}

class UpdateState {
  const UpdateState({
    this.status = UpdateStatus.loading,
    this.installedVersion = 'Loading...',
    this.installedBuild = 0,
    this.release,
    this.progress = 0,
    this.message,
  });

  final UpdateStatus status;
  final String installedVersion;
  final int installedBuild;
  final DesktopRelease? release;
  final double progress;
  final String? message;

  UpdateState copyWith({
    UpdateStatus? status,
    String? installedVersion,
    int? installedBuild,
    DesktopRelease? release,
    double? progress,
    String? message,
  }) => UpdateState(
    status: status ?? this.status,
    installedVersion: installedVersion ?? this.installedVersion,
    installedBuild: installedBuild ?? this.installedBuild,
    release: release ?? this.release,
    progress: progress ?? this.progress,
    message: message,
  );
}

bool isUpdateAvailable(int installedBuild, DesktopRelease release) =>
    release.build > installedBuild;

bool isSecureUpdateOrigin(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return false;
  if (uri.scheme == 'https') return true;
  if (uri.scheme != 'http') return false;
  if (uri.host == 'localhost') return true;
  return InternetAddress.tryParse(uri.host)?.isLoopback ?? false;
}

Future<bool> verifyArtifact(File file, ReleaseArtifact artifact) async {
  if (await file.length() != artifact.size) return false;
  final digest = await sha256.bind(file.openRead()).first;
  return digest.toString() == artifact.sha256;
}

Future<File> updateArtifactDestination(
  ReleaseArtifact artifact, {
  Directory? applicationSupportDirectory,
}) async {
  final support =
      applicationSupportDirectory ?? await getApplicationSupportDirectory();
  final updates = Directory('${support.path}${Platform.pathSeparator}updates');
  await updates.create(recursive: true);
  return File('${updates.path}${Platform.pathSeparator}${artifact.filename}');
}

Future<bool> canWriteUpdateBeside(String executablePath) async {
  final parent = File(executablePath).parent;
  final probe = File(
    '${parent.path}${Platform.pathSeparator}.watchparty-update-$pid.tmp',
  );
  try {
    await probe.writeAsBytes(const [0], flush: true);
    await probe.delete();
    return true;
  } catch (_) {
    if (await probe.exists()) {
      try {
        await probe.delete();
      } catch (_) {}
    }
    return false;
  }
}

final desktopUpdateProvider =
    StateNotifierProvider<DesktopUpdateController, UpdateState>(
      (ref) => DesktopUpdateController(ref.read(apiClientProvider)),
    );

class DesktopUpdateController extends StateNotifier<UpdateState> {
  DesktopUpdateController(this._api) : super(const UpdateState()) {
    _loadInstalledVersion();
  }

  final ApiClient _api;

  String? get _platform => Platform.isWindows
      ? 'windows'
      : Platform.isLinux
      ? 'linux'
      : Platform.isMacOS
      ? 'macos'
      : null;

  Future<void> _loadInstalledVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      state = state.copyWith(
        status: UpdateStatus.idle,
        installedVersion: '${info.version}+${info.buildNumber}',
        installedBuild: int.tryParse(info.buildNumber) ?? 0,
      );
    } catch (_) {
      if (mounted) {
        state = state.copyWith(
          status: UpdateStatus.error,
          installedVersion: 'Unknown',
          message: 'Could not read the installed version.',
        );
      }
    }
  }

  Future<void> check() async {
    if (_platform == null) return;
    if (state.status == UpdateStatus.loading) await _loadInstalledVersion();
    if (!isSecureUpdateOrigin(_api.baseUrl)) {
      state = state.copyWith(
        status: UpdateStatus.error,
        message: 'Updates require HTTPS (HTTP is allowed only on loopback).',
      );
      return;
    }
    state = state.copyWith(status: UpdateStatus.checking, progress: 0);
    try {
      final release = DesktopRelease.fromJson(
        await _api.currentDesktopRelease(),
      );
      if (!release.artifacts.containsKey(_platform)) {
        throw const FormatException('No update for this platform');
      }
      state = state.copyWith(
        status: isUpdateAvailable(state.installedBuild, release)
            ? UpdateStatus.available
            : UpdateStatus.upToDate,
        release: release,
        message: isUpdateAvailable(state.installedBuild, release)
            ? 'Version ${release.version} is available.'
            : 'Watchparty is up to date.',
      );
    } catch (error) {
      state = state.copyWith(
        status: UpdateStatus.error,
        message: 'Update check failed: $error',
      );
    }
  }

  Future<void> install() async {
    final release = state.release;
    final platform = _platform;
    if (release == null || platform == null) return;
    final artifact = release.artifacts[platform]!;
    File? file;
    try {
      final appImage = Platform.environment['APPIMAGE'];
      if (Platform.isLinux &&
          appImage != null &&
          appImage.isNotEmpty &&
          await canWriteUpdateBeside(appImage)) {
        file = File('$appImage.update');
      } else {
        file = await updateArtifactDestination(artifact);
      }
      if (await file.exists()) await file.delete();
      state = state.copyWith(
        status: UpdateStatus.downloading,
        progress: 0,
        message: 'Downloading update...',
      );
      await _api.downloadDesktopArtifact(
        artifact.url,
        file.path,
        onProgress: (received, total) {
          if (!mounted) return;
          final expected = total > 0 ? total : artifact.size;
          state = state.copyWith(
            status: UpdateStatus.downloading,
            progress: (received / expected).clamp(0, 1),
            message: 'Downloading update...',
          );
        },
      );
      if (!await verifyArtifact(file, artifact)) {
        await file.delete();
        throw const FormatException('download size or SHA-256 did not match');
      }
      await _applyVerified(file);
    } catch (error) {
      if (file != null && await file.exists()) {
        await file.delete();
      }
      state = state.copyWith(
        status: UpdateStatus.error,
        message: 'Update failed: $error',
      );
    }
  }

  Future<void> _applyVerified(File file) async {
    if (Platform.isWindows) {
      await Process.start(file.path, const [
        '/VERYSILENT',
        '/SUPPRESSMSGBOXES',
        '/CLOSEAPPLICATIONS',
        '/RESTARTAPPLICATIONS',
      ], mode: ProcessStartMode.detached);
      await DesktopLifecycle.instance.quitForUpdate();
      return;
    }

    if (Platform.isLinux) {
      final appImage = Platform.environment['APPIMAGE'];
      if (appImage != null &&
          appImage.isNotEmpty &&
          file.path == '$appImage.update') {
        final chmod = await Process.run('chmod', ['+x', file.path]);
        if (chmod.exitCode != 0) {
          throw StateError('could not make AppImage executable');
        }
        await file.rename(appImage);
        await Process.start(
          appImage,
          const [],
          mode: ProcessStartMode.detached,
        );
        await DesktopLifecycle.instance.quitForUpdate();
        return;
      }
      var revealed = true;
      try {
        final result = await Process.run('xdg-open', [file.parent.path]);
        revealed = result.exitCode == 0;
      } catch (_) {
        revealed = false;
      }
      state = state.copyWith(
        status: UpdateStatus.manualInstall,
        progress: 1,
        message: revealed
            ? 'Downloaded and verified. This install is not an AppImage, so replace or install it manually.'
            : 'Downloaded and verified to ${file.path}. This install is not an AppImage; open that folder and install it manually.',
      );
      return;
    }

    var opened = true;
    try {
      final result = await Process.run('open', [file.path]);
      opened = result.exitCode == 0;
    } catch (_) {
      opened = false;
    }
    state = state.copyWith(
      status: UpdateStatus.manualInstall,
      progress: 1,
      message: opened
          ? 'Verified DMG opened. Quit Watchparty, then drag the new app to Applications to replace it.'
          : 'Verified DMG saved to ${file.path}. Open it, quit Watchparty, then drag the new app to Applications.',
    );
  }
}
