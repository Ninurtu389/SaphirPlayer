import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import '../../core/constants/app_spacing.dart';

typedef MkvExtractedTags = ({Map<String, String> tags, int? durationMs});

class MkvEbmlTagParser {
  MkvEbmlTagParser._();

  static const int _ebmlHeaderId = 0x1A45DFA3;
  static const int _segmentId = 0x18538067;
  static const int _seekHeadId = 0x114D9B74;
  static const int _seekId = 0x4DBB;
  static const int _seekElementId = 0x53AB;
  static const int _seekPositionId = 0x53AC;
  static const int _segmentInfoId = 0x1549A966;
  static const int _timestampScaleId = 0x2AD7B1;
  static const int _durationId = 0x4489;
  static const int _titleId = 0x7BA9;
  static const int _tagsId = 0x1254C367;
  static const int _tagId = 0x7373;
  static const int _simpleTagId = 0x67C8;
  static const int _tagNameId = 0x45A3;
  static const int _tagStringId = 0x4487;
  static const int _clusterId = 0x1F43B675;

  static MkvExtractedTags? readFile(String filePath) {
    RandomAccessFile? raf;
    try {
      final file = File(filePath);
      if (!file.existsSync()) return null;
      final fileLength = file.lengthSync();
      if (fileLength <= 0) return null;
      raf = file.openSync(mode: FileMode.read);
      final initialSize =
          math.min(fileLength, AppSpacing.mkvTagHeaderMaxScanBytes);
      final headerBytes = raf.readSync(initialSize);
      return _parse(headerBytes, raf: raf, fileLength: fileLength);
    } on FileSystemException {
      return null;
    } finally {
      try {
        raf?.closeSync();
      } on FileSystemException {
        // Ignore close errors
      }
    }
  }

  static MkvExtractedTags? parseBytes(Uint8List bytes) {
    if (bytes.isEmpty) return null;
    return _parse(bytes, fileLength: bytes.length);
  }

  static MkvExtractedTags? _parse(
    Uint8List bytes, {
    RandomAccessFile? raf,
    required int fileLength,
  }) {
    final header = _readVintId(bytes, 0);
    if (header == null || header.id != _ebmlHeaderId) return null;
    final headerSize = _readVintSize(bytes, header.nextOffset);
    if (headerSize == null || headerSize.size < 0) return null;
    var offset = headerSize.nextOffset + headerSize.size;

    int? segmentDataStart;
    int segmentEnd = bytes.length;
    while (offset < bytes.length) {
      final elemId = _readVintId(bytes, offset);
      final elemSize =
          elemId != null ? _readVintSize(bytes, elemId.nextOffset) : null;
      if (elemId == null || elemSize == null) return null;
      if (elemId.id == _segmentId) {
        segmentDataStart = elemSize.nextOffset;
        segmentEnd = elemSize.size >= 0
            ? math.min(bytes.length, segmentDataStart + elemSize.size)
            : bytes.length;
        break;
      }
      if (elemSize.size < 0) return null;
      offset = elemSize.nextOffset + elemSize.size;
    }
    if (segmentDataStart == null) return null;

    final acc = _MkvParseState();
    final seekOffsets = <int, int>{};

    _forEachChild(bytes, segmentDataStart, segmentEnd, (id, cStart, cEnd) {
      if (id == _clusterId) return false;
      _handleSegmentChild(bytes, id, cStart, cEnd, acc, seekOffsets);
      return true;
    });

    _resolveSeekTargets(
      bytes,
      raf: raf,
      fileLength: fileLength,
      segmentDataStart: segmentDataStart,
      acc: acc,
      seekOffsets: seekOffsets,
    );

    if (acc.infoTitle != null && acc.infoTitle!.isNotEmpty) {
      acc.tags.putIfAbsent('title', () => acc.infoTitle!);
    }
    int? durationMs;
    if (acc.durationUnits != null &&
        acc.durationUnits! > 0 &&
        acc.durationUnits!.isFinite) {
      durationMs = (acc.durationUnits! * acc.timestampScale / 1000000.0).round();
    }
    if (acc.tags.isEmpty && durationMs == null) return null;
    return (tags: acc.tags, durationMs: durationMs);
  }

  static void _resolveSeekTargets(
    Uint8List initialBytes, {
    required RandomAccessFile? raf,
    required int fileLength,
    required int segmentDataStart,
    required _MkvParseState acc,
    required Map<int, int> seekOffsets,
  }) {
    var budget = AppSpacing.mkvTagHeaderMaxScanBytes;
    for (final targetId in [_segmentInfoId, _tagsId]) {
      final found = targetId == _segmentInfoId ? acc.foundInfo : acc.foundTags;
      final relPos = seekOffsets[targetId];
      if (found || relPos == null || relPos < 0) continue;
      final absPos = segmentDataStart + relPos;
      if (absPos < 0 || absPos >= fileLength) continue;

      Uint8List? chunk;
      var chunkOffset = 0;
      if (absPos < initialBytes.length) {
        chunk = initialBytes;
        chunkOffset = absPos;
      } else if (raf != null && budget > 0) {
        final toRead = math.min(budget, fileLength - absPos);
        raf.setPositionSync(absPos);
        chunk = raf.readSync(toRead);
        budget -= chunk.length;
      }
      if (chunk == null) continue;

      final idRes = _readVintId(chunk, chunkOffset);
      if (idRes == null || idRes.id != targetId) continue;
      final sizeRes = _readVintSize(chunk, idRes.nextOffset);
      if (sizeRes == null || sizeRes.size < 0) continue;
      final end = sizeRes.nextOffset + sizeRes.size;
      if (end <= chunk.length) {
        _handleSegmentChild(
          chunk,
          targetId,
          sizeRes.nextOffset,
          end,
          acc,
          seekOffsets,
        );
      }
    }
  }

  static void _handleSegmentChild(
    Uint8List bytes,
    int id,
    int start,
    int end,
    _MkvParseState acc,
    Map<int, int> seekOffsets,
  ) {
    if (id == _seekHeadId) {
      _forEachChild(bytes, start, end, (childId, cStart, cEnd) {
        if (childId == _seekId) {
          int? targetId;
          int? targetPos;
          _forEachChild(bytes, cStart, cEnd, (fId, fStart, fEnd) {
            if (fId == _seekElementId) {
              targetId = _readUint(bytes, fStart, fEnd - fStart);
            } else if (fId == _seekPositionId) {
              targetPos = _readUint(bytes, fStart, fEnd - fStart);
            }
            return true;
          });
          if (targetId != null && targetPos != null) {
            seekOffsets.putIfAbsent(targetId!, () => targetPos!);
          }
        }
        return true;
      });
    } else if (id == _segmentInfoId) {
      acc.foundInfo = true;
      _forEachChild(bytes, start, end, (childId, cStart, cEnd) {
        final len = cEnd - cStart;
        if (childId == _timestampScaleId) {
          final scale = _readUint(bytes, cStart, len);
          if (scale > 0) acc.timestampScale = scale;
        } else if (childId == _durationId) {
          acc.durationUnits = _readFloat(bytes, cStart, len);
        } else if (childId == _titleId) {
          final title = _readUtf8(bytes, cStart, len);
          if (title.isNotEmpty) acc.infoTitle = title;
        }
        return true;
      });
    } else if (id == _tagsId) {
      acc.foundTags = true;
      _forEachChild(bytes, start, end, (childId, cStart, cEnd) {
        if (childId == _tagId) {
          _forEachChild(bytes, cStart, cEnd, (tId, tStart, tEnd) {
            if (tId == _simpleTagId) {
              _parseSimpleTag(bytes, tStart, tEnd, acc.tags);
            }
            return true;
          });
        }
        return true;
      });
    }
  }

  static void _parseSimpleTag(
    Uint8List bytes,
    int start,
    int end,
    Map<String, String> out,
  ) {
    String? name;
    String? value;
    _forEachChild(bytes, start, end, (id, cStart, cEnd) {
      final len = cEnd - cStart;
      if (id == _tagNameId) {
        name = _readUtf8(bytes, cStart, len);
      } else if (id == _tagStringId) {
        value = _readUtf8(bytes, cStart, len);
      } else if (id == _simpleTagId) {
        _parseSimpleTag(bytes, cStart, cEnd, out);
      }
      return true;
    });
    if (name != null &&
        name!.trim().isNotEmpty &&
        value != null &&
        value!.trim().isNotEmpty) {
      out.putIfAbsent(name!.trim(), () => value!.trim());
    }
  }

  static void _forEachChild(
    Uint8List bytes,
    int start,
    int end,
    bool Function(int id, int childStart, int childEnd) onChild,
  ) {
    var pos = start;
    while (pos < end) {
      final idRes = _readVintId(bytes, pos);
      if (idRes == null) break;
      final sizeRes = _readVintSize(bytes, idRes.nextOffset);
      if (sizeRes == null || sizeRes.size < 0) break;
      final childStart = sizeRes.nextOffset;
      final childEnd = childStart + sizeRes.size;
      if (childEnd > end) break;
      if (!onChild(idRes.id, childStart, childEnd)) break;
      pos = childEnd;
    }
  }

  static ({int id, int nextOffset})? _readVintId(Uint8List bytes, int offset) {
    if (offset >= bytes.length) return null;
    final first = bytes[offset];
    if (first == 0) return null;
    var length = 1;
    var mask = 0x80;
    while ((first & mask) == 0) {
      mask >>= 1;
      if (++length > 4) return null;
    }
    if (offset + length > bytes.length) return null;
    var value = 0;
    for (var i = 0; i < length; i++) {
      value = (value << 8) | bytes[offset + i];
    }
    return (id: value, nextOffset: offset + length);
  }

  static ({int size, int nextOffset})? _readVintSize(
    Uint8List bytes,
    int offset,
  ) {
    if (offset >= bytes.length) return null;
    final first = bytes[offset];
    if (first == 0) return null;
    var length = 1;
    var mask = 0x80;
    while ((first & mask) == 0) {
      mask >>= 1;
      if (++length > 8) return null;
    }
    if (offset + length > bytes.length) return null;
    var value = first & (mask - 1);
    var allOnes = value == (mask - 1);
    for (var i = 1; i < length; i++) {
      final b = bytes[offset + i];
      if (b != 0xFF) allOnes = false;
      value = (value << 8) | b;
    }
    return (size: allOnes ? -1 : value, nextOffset: offset + length);
  }

  static int _readUint(Uint8List bytes, int offset, int length) {
    var result = 0;
    for (var i = 0; i < length; i++) {
      result = (result << 8) | bytes[offset + i];
    }
    return result;
  }

  static double? _readFloat(Uint8List bytes, int offset, int length) {
    if (length == 4) {
      return ByteData.sublistView(bytes, offset, offset + 4)
          .getFloat32(0, Endian.big);
    }
    if (length == 8) {
      return ByteData.sublistView(bytes, offset, offset + 8)
          .getFloat64(0, Endian.big);
    }
    return null;
  }

  static String _readUtf8(Uint8List bytes, int offset, int length) {
    final slice = bytes.sublist(offset, offset + length);
    return utf8.decode(slice, allowMalformed: true).replaceAll('\x00', '').trim();
  }
}

class _MkvParseState {
  bool foundInfo = false;
  bool foundTags = false;
  int timestampScale = 1000000;
  double? durationUnits;
  String? infoTitle;
  final Map<String, String> tags = {};
}
