import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import '../progress_callback/compress_mixin.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../media/media_info.dart';

abstract class IVideoCompress extends CompressMixin {}

class _VideoCompressImpl extends IVideoCompress {
  _VideoCompressImpl._() {
    initProcessCallback();
  }

  static _VideoCompressImpl? _instance;

  static _VideoCompressImpl get instance {
    return _instance ??= _VideoCompressImpl._();
  }

  static void _dispose() {
    _instance = null;
  }
}

// ignore: non_constant_identifier_names
IVideoCompress get VideoCompress => _VideoCompressImpl.instance;

extension Compress on IVideoCompress {
  void dispose() {
    _VideoCompressImpl._dispose();
  }

  Future<T?> _invoke<T>(String name, [Map<String, dynamic>? params]) async {
    T? result;
    try {
      result = params != null
          ? await channel.invokeMethod(name, params)
          : await channel.invokeMethod(name);
    } on PlatformException catch (e) {
      debugPrint('''Error from VideoCompress: 
      Method: $name
      $e''');
    }
    return result;
  }

  /// getByteThumbnail return [Future<Uint8List>],
  /// quality can be controlled by [quality] from 1 to 100,
  /// select the position unit in the video by [position] is seconds
  Future<Uint8List?> getByteThumbnail(
    String path, {
    int quality = 100,
    int position = -1,
  }) async {
    assert(quality > 1 || quality < 100);

    return await _invoke<Uint8List>('getByteThumbnail', {
      'path': path,
      'quality': quality,
      'position': position,
    });
  }

  /// getFileThumbnail return [Future<File>]
  /// quality can be controlled by [quality] from 1 to 100,
  /// select the position unit in the video by [position] is seconds
  Future<File> getFileThumbnail(
    String path, {
    required int sessionId,
    int quality = 100,
    int position = -1,
  }) async {
    assert(quality > 1 || quality < 100);

    // Not to set the result as strong-mode so that it would have exception to
    // lead to the failure of compression
    final filePath = await (_invoke<String>('getFileThumbnail', {
      'path': path,
      'sessionId': sessionId,
      'quality': quality,
      'position': position,
    }));

    final file = File(filePath!);

    return file;
  }

  /// get media information from [path]
  ///
  /// get media information from [path] return [Future<MediaInfo>]
  ///
  /// ## example
  /// ```dart
  /// final info = await _flutterVideoCompress.getMediaInfo(file.path);
  /// debugPrint(info.toJson());
  /// ```
  Future<MediaInfo> getMediaInfo(String path) async {
    // Not to set the result as strong-mode so that it would have exception to
    // lead to the failure of compression
    final jsonStr = await (_invoke<String>('getMediaInfo', {'path': path}));
    final jsonMap = json.decode(jsonStr!);
    return MediaInfo.fromJson(jsonMap);
  }

  /// compress video from [path]
  /// compress video from [path] return [Future<MediaInfo>]
  ///
  /// [rotation] is clockwise, 0,90,180,270
  ///
  /// ## example
  /// ```dart
  /// final info = await _flutterVideoCompress.compressVideo(
  ///   file.path,
  /// );
  /// debugPrint(info.toJson());
  /// ```
  Future<MediaInfo?> compressVideo(
    String path, {
    required int sessionId,
    double? startTimeMs,
    double? endTimeMs,
    bool? includeAudio = true,
    int? rotation,
  }) async {
    if (isCompressing) {
      throw StateError('''VideoCompress Error: 
      Method: compressVideo
      Already have a compression process, you need to wait for the process to finish or stop it''');
    }

    if (compressProgress$.notSubscribed) {
      debugPrint('''VideoCompress: You can try to subscribe to the 
      compressProgress\$ stream to know the compressing state.''');
    }
    // ignore: invalid_use_of_protected_member
    setProcessingStatus(true);
    final jsonStr = await _invoke<String>('compressVideo', {
      'path': path,
      'sessionId': sessionId,
      'startTimeMs': startTimeMs,
      'endTimeMs': endTimeMs,
      'includeAudio': includeAudio,
      'rotation': rotation,
    });

    // ignore: invalid_use_of_protected_member
    setProcessingStatus(false);

    if (jsonStr != null) {
      final jsonMap = json.decode(jsonStr);
      return MediaInfo.fromJson(jsonMap);
    } else {
      return null;
    }
  }

  /// stop compressing the file that is currently being compressed.
  /// If there is no compression process, nothing will happen.
  Future<void> cancelCompression() async {
    await _invoke<void>('cancelCompression');
  }

  /// delete the cache folder, please do not put other things
  /// in the folder of this plugin, it will be cleared
  Future<bool?> deleteSessionCache({
    required int sessionId,
  }) async {
    return await _invoke<bool>('deleteSessionCache', {
      'sessionId': sessionId,
    });
  }

  Future<void> setLogLevel(int logLevel) async {
    return await _invoke<void>('setLogLevel', {
      'logLevel': logLevel,
    });
  }
}
