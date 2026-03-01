import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/services.dart';

// ignore: depend_on_referenced_packages
import 'package:path/path.dart' as path;

import 'package:storypad/core/services/logger/app_logger.dart';
import 'package:storypad/core/types/support_directory_path.dart';

enum FirestoreStorageState { success, connectionFailed, unauthorized, unknown }

class FirestoreStorageResponse {
  final File? file;
  final FirestoreStorageState state;

  bool get success => file != null;
  bool get unauthorized => state == FirestoreStorageState.unauthorized;
  bool get connectionFailed => state == FirestoreStorageState.connectionFailed;

  FirestoreStorageResponse({
    required this.file,
    this.state = FirestoreStorageState.success,
  });
}

class FirestoreStorageService {
  static const int MAX_DOWNLOAD_SIZE = 20 * 1024 * 1024; // 20mb

  static FirestoreStorageService instance = FirestoreStorageService();

  Map<String, dynamic>? _hash;
  Map<String, String>? _downloadUrlsByUrlPath;

  final Map<String, Completer<FirestoreStorageResponse>> _downloadingFileByUrlPath = {};

  Future<void> loadHash() async {
    _hash = await rootBundle
        .loadString('assets/firestore_storage_map.json')
        .then((jsonString) => json.decode(jsonString));
  }

  // input: /relax_sounds/animal/forest_birds.svg
  // output: /relax_sounds/animal/forest_birds-xxxx.svg
  String? getHashPath(String originalUrlPath) {
    if (_hash == null) return null;
    return _hash![originalUrlPath] as String?;
  }

  File? getCachedFile(String urlPath) {
    final String? hashPath = getHashPath(urlPath);
    if (hashPath == null) return null;

    final String downloadPath = constructDeviceDownloadPath(hashPath);
    if (File(downloadPath).existsSync()) return File(downloadPath);
    return null;
  }

  Future<String?> getDownloadURL(String urlPath) async {
    _downloadUrlsByUrlPath ??= {};

    try {
      final cached = _downloadUrlsByUrlPath![urlPath];
      if (cached != null) return cached;

      final String? hashPath = getHashPath(urlPath);
      if (hashPath == null) {
        AppLogger.warning(
          'FirestoreStorageService#getDownloadURL missing hash for $urlPath',
        );
        return null;
      }

      final storageRef = FirebaseStorage.instance.ref().child(hashPath);
      final downloadUrl = await storageRef.getDownloadURL();

      _downloadUrlsByUrlPath![urlPath] = downloadUrl;
      return downloadUrl;
    } on FirebaseException catch (e, s) {
      AppLogger.error(
        "FirestoreStorageService#getDownloadURL code: ${e.code}, message: ${e.message}, plugin: ${e.plugin}",
        stackTrace: s,
      );
      return null;
    } catch (e, s) {
      AppLogger.error(e.toString(), stackTrace: s);
      return null;
    }
  }

  Future<FirestoreStorageResponse> downloadFile(String urlPath) async {
    assert(urlPath.startsWith("/"));

    final String? hashPath = getHashPath(urlPath);
    if (hashPath == null) {
      return FirestoreStorageResponse(
        file: null,
        state: FirestoreStorageState.unknown,
      );
    }

    final String downloadPath = constructDeviceDownloadPath(hashPath);

    if (File(downloadPath).existsSync()) {
      return FirestoreStorageResponse(file: File(downloadPath));
    }

    if (!File(downloadPath).parent.existsSync()) {
      await File(downloadPath).parent.create(recursive: true);
    }

    final existingCompleter = _downloadingFileByUrlPath[urlPath];
    if (existingCompleter != null && !existingCompleter.isCompleted) {
      return existingCompleter.future;
    }

    final completer = Completer<FirestoreStorageResponse>();
    _downloadingFileByUrlPath[urlPath] = completer;

    FirestoreStorageResponse response;

    try {
      final childRef = FirebaseStorage.instance.ref().child(hashPath);
      final content = await childRef.getData(MAX_DOWNLOAD_SIZE);

      if (content != null) {
        await File(downloadPath).writeAsBytes(content);
        response = FirestoreStorageResponse(file: File(downloadPath));
      } else {
        response = FirestoreStorageResponse(
          file: null,
          state: FirestoreStorageState.unknown,
        );
      }
    } on FirebaseException catch (e, s) {
      AppLogger.error(
        "🔴 FirestoreStorageService#downloadFile code: ${e.code}, message: ${e.message}, plugin: ${e.plugin}",
        stackTrace: s,
      );
      response = FirestoreStorageResponse(
        file: null,
        state: e.code == 'unauthorized'
            ? FirestoreStorageState.unauthorized
            : FirestoreStorageState.unknown,
      );
    } catch (e, s) {
      AppLogger.error(
        "🔴 FirestoreStorageService#downloadFile error: $e",
        stackTrace: s,
      );
      response = FirestoreStorageResponse(
        file: null,
        state: FirestoreStorageState.unknown,
      );
    }

    completer.complete(response);
    return response;
  }

  String constructDeviceDownloadPath(String path) {
    return '${SupportDirectoryPath.downloaded_from_firestore.directory.path}$path';
  }

  Future<List<String>> cleanupUnusedFiles() async {
    try {
      final downloadDir = SupportDirectoryPath.downloaded_from_firestore.directory;
      if (!await downloadDir.exists()) return [];

      final validBasenames =
          (_hash ?? {}).values.map((e) => path.basename(e.toString())).toSet();

      final files = await downloadDir
          .list(recursive: true)
          .where((entity) => entity is File)
          .toList();

      final deletedFiles = <String>[];

      for (final fileEntity in files) {
        final filename = path.basename(fileEntity.path);
        if (validBasenames.contains(filename)) continue;

        try {
          await fileEntity.delete();
          deletedFiles.add(filename);
        } catch (e, s) {
          AppLogger.error(
            '$runtimeType#cleanupUnusedFiles failed to delete ${fileEntity.path}: $e',
            stackTrace: s,
          );
        }
      }

      AppLogger.info(
        '$runtimeType#cleanupUnusedFiles ${deletedFiles.length} unused files removed',
      );
      return deletedFiles;
    } catch (e, s) {
      AppLogger.error('$runtimeType#cleanupUnusedFiles error: $e', stackTrace: s);
      return [];
    }
  }
}