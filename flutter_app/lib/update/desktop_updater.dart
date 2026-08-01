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

/// The installed `.app` bundle containing [executablePath].
///
/// `Platform.resolvedExecutable` inside a bundle is
/// `…/Watchparty.app/Contents/MacOS/Watchparty`, so the bundle is three levels
/// up. Returns null when the layout isn't a bundle (a bare binary from
/// `flutter run`), which is the signal to fall back to a manual install rather
/// than guess at a path and delete the wrong thing.
String? macAppBundlePath(String executablePath) {
  final parts = executablePath.split('/');
  final macos = parts.length - 2;
  if (macos < 1) return null;
  if (parts[macos] != 'MacOS' || parts[macos - 1] != 'Contents') return null;
  final bundle = parts.sublist(0, macos - 1).join('/');
  return bundle.endsWith('.app') ? bundle : null;
}

/// Shell script that swaps the bundle once THIS process has exited.
///
/// The running app cannot replace its own bundle while it holds it open, so the
/// same trick the Windows installer uses applies here: hand the work to a
/// detached process that waits for our pid to disappear. Quarantine is stripped
/// from the staged copy because the DMG it came out of is flagged as downloaded;
/// the bytes were already verified against the release's SHA-256 before we got
/// here, so the flag would only block an update the user explicitly asked for.
String macSwapScript({
  required int pid,
  required String stagedApp,
  required String installedApp,
}) => '''
#!/bin/sh
set -e
while kill -0 $pid 2>/dev/null; do sleep 0.2; done
/usr/bin/xattr -dr com.apple.quarantine '$stagedApp' 2>/dev/null || true
/bin/rm -rf '$installedApp'
/usr/bin/ditto '$stagedApp' '$installedApp'
/bin/rm -rf '$stagedApp'
/usr/bin/open '$installedApp'
''';

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

    await _applyMacVerified(file);
  }

  /// Mount the verified DMG, stage the new bundle, and let a detached script
  /// swap it in once we exit. Falls back to revealing the DMG whenever any step
  /// can't be done safely — a failed self-update must leave the working install
  /// alone, not half-replaced.
  Future<void> _applyMacVerified(File dmg) async {
    final installed = macAppBundlePath(Platform.resolvedExecutable);
    String? mountPoint;
    try {
      if (installed == null) return _revealMacDmg(dmg, 'this build is not an app bundle');

      final attach = await Process.run('hdiutil', [
        'attach', dmg.path, '-nobrowse', '-readonly', '-mountrandom', '/tmp',
      ]);
      if (attach.exitCode != 0) return _revealMacDmg(dmg, 'the disk image would not mount');
      mountPoint = _mountPointFrom(attach.stdout.toString());
      if (mountPoint == null) return _revealMacDmg(dmg, 'the mounted image had no volume');

      final source = await Directory(mountPoint)
          .list()
          .where((e) => e.path.endsWith('.app'))
          .cast<FileSystemEntity?>()
          .firstWhere((e) => e != null, orElse: () => null);
      if (source == null) return _revealMacDmg(dmg, 'the disk image had no app in it');

      // Stage beside the install so the swap is a local move, and so a failure
      // here happens before anything touches the working copy.
      final staged = '${(await getApplicationSupportDirectory()).path}/updates/Watchparty-new.app';
      await Directory(staged).parent.create(recursive: true);
      final ditto = await Process.run('ditto', [source.path, staged]);
      if (ditto.exitCode != 0) return _revealMacDmg(dmg, 'the new app could not be staged');

      final script = File('${(await getTemporaryDirectory()).path}/watchparty-update.sh');
      await script.writeAsString(macSwapScript(
        pid: pid,
        stagedApp: staged,
        installedApp: installed,
      ));
      await Process.run('chmod', ['+x', script.path]);
      await Process.start('/bin/sh', [script.path], mode: ProcessStartMode.detached);
      await DesktopLifecycle.instance.quitForUpdate();
    } catch (error) {
      await _revealMacDmg(dmg, '$error');
    } finally {
      if (mountPoint != null) {
        await Process.run('hdiutil', ['detach', mountPoint, '-quiet']).catchError((_) =>
            ProcessResult(0, 0, '', ''));
      }
    }
  }

  /// hdiutil prints a tab-separated table; the mount point is the last field of
  /// the line that has one.
  static String? _mountPointFrom(String attachOutput) {
    for (final line in attachOutput.split('\n')) {
      final fields = line.split('\t').where((f) => f.trim().isNotEmpty).toList();
      if (fields.length >= 2 && fields.last.trim().startsWith('/')) {
        return fields.last.trim();
      }
    }
    return null;
  }

  Future<void> _revealMacDmg(File dmg, String why) async {
    var opened = true;
    try {
      final result = await Process.run('open', [dmg.path]);
      opened = result.exitCode == 0;
    } catch (_) {
      opened = false;
    }
    state = state.copyWith(
      status: UpdateStatus.manualInstall,
      progress: 1,
      message: opened
          ? 'Verified DMG opened ($why). Quit Watchparty, then drag the new app to Applications.'
          : 'Verified DMG saved to ${dmg.path} ($why). Open it, quit Watchparty, then drag the new app to Applications.',
    );
  }
}
