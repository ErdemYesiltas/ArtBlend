import 'dart:convert';
import 'dart:typed_data';

/// A reference between objects of a keyed archive.
class PlistUid {
  const PlistUid(this.value);
  final int value;
  @override
  bool operator ==(Object other) => other is PlistUid && other.value == value;
  @override
  int get hashCode => value.hashCode;
}

/// Apple's binary property list (`bplist00`): dictionaries, arrays,
/// strings, numbers, booleans, data and archive references.
Object? readBinaryPlist(Uint8List bytes) {
  if (bytes.length < 40 || latin1.decode(bytes.sublist(0, 6)) != 'bplist') {
    throw const FormatException('Not a binary property list');
  }
  final data = ByteData.sublistView(bytes);
  final trailer = bytes.length - 32;
  final offsetSize = bytes[trailer + 6], refSize = bytes[trailer + 7];
  final count = data.getUint64(trailer + 8);
  final top = data.getUint64(trailer + 16);
  final table = data.getUint64(trailer + 24);
  if (count > 1 << 20 || table + count * offsetSize > bytes.length) {
    throw const FormatException('Damaged property list');
  }
  int sized(int at, int size) {
    var v = 0;
    for (var i = 0; i < size; i++) {
      v = v << 8 | bytes[at + i];
    }
    return v;
  }

  int offset(int ref) => sized(table + ref * offsetSize, offsetSize);
  final seen = <int>{};

  Object? read(int ref, int depth) {
    if (depth > 64 || ref >= count) {
      throw const FormatException('Damaged property list');
    }
    var at = offset(ref);
    final marker = bytes[at], kind = marker >> 4, info = marker & 0xf;
    at++;
    int length() {
      if (info != 0xf) return info;
      final size = 1 << (bytes[at] & 0xf);
      final v = sized(at + 1, size);
      at += 1 + size;
      return v;
    }

    switch (kind) {
      case 0x0:
        return switch (info) {
          0x8 => false,
          0x9 => true,
          _ => null,
        };
      case 0x1:
        final size = 1 << info;
        return size == 8 ? data.getInt64(at) : sized(at, size);
      case 0x2:
        return info == 2 ? data.getFloat32(at) : data.getFloat64(at);
      case 0x3:
        return data.getFloat64(at);
      case 0x4:
        final n = length();
        return Uint8List.fromList(bytes.sublist(at, at + n));
      case 0x5:
        final n = length();
        return latin1.decode(bytes.sublist(at, at + n));
      case 0x6:
        final n = length();
        return String.fromCharCodes([
          for (var i = 0; i < n; i++) data.getUint16(at + i * 2),
        ]);
      case 0x8:
        return PlistUid(sized(at, info + 1));
      case 0xa:
        final n = length();
        if (!seen.add(ref)) throw const FormatException('Cyclic list');
        final list = [
          for (var i = 0; i < n; i++)
            read(sized(at + i * refSize, refSize), depth + 1),
        ];
        seen.remove(ref);
        return list;
      case 0xd:
        final n = length();
        if (!seen.add(ref)) throw const FormatException('Cyclic dictionary');
        final map = <String, Object?>{};
        for (var i = 0; i < n; i++) {
          final key = read(sized(at + i * refSize, refSize), depth + 1);
          map['$key'] = read(sized(at + (n + i) * refSize, refSize), depth + 1);
        }
        seen.remove(ref);
        return map;
    }
    throw FormatException(
      'Unsupported property list object 0x${marker.toRadixString(16)}',
    );
  }

  return read(top, 0);
}

/// [root] (maps with string keys, lists, strings, ints, doubles, bools,
/// [Uint8List]s, [PlistUid]s) as a binary property list.
Uint8List writeBinaryPlist(Object root) {
  final objects = <Uint8List>[];
  final out = BytesBuilder();

  // Every object gets its own entry; references are 2 bytes.
  int add(Object? value) {
    final index = objects.length;
    objects.add(Uint8List(0));
    final b = BytesBuilder();
    void header(int kind, int n) {
      if (n < 15) {
        b.addByte(kind << 4 | n);
      } else {
        b.addByte(kind << 4 | 0xf);
        b
          ..addByte(0x12)
          ..add([n >> 24 & 0xff, n >> 16 & 0xff, n >> 8 & 0xff, n & 0xff]);
      }
    }

    void ref(int r) => b.add([r >> 8 & 0xff, r & 0xff]);
    switch (value) {
      case null:
        b.addByte(0x00);
      case bool v:
        b.addByte(v ? 0x09 : 0x08);
      case int v:
        b.addByte(0x13);
        final d = ByteData(8)..setInt64(0, v);
        b.add(d.buffer.asUint8List());
      case double v:
        b.addByte(0x23);
        final d = ByteData(8)..setFloat64(0, v);
        b.add(d.buffer.asUint8List());
      case PlistUid v:
        b
          ..addByte(0x83)
          ..add([
            v.value >> 24 & 0xff,
            v.value >> 16 & 0xff,
            v.value >> 8 & 0xff,
            v.value & 0xff,
          ]);
      case Uint8List v:
        header(0x4, v.length);
        b.add(v);
      case String v:
        if (v.codeUnits.every((u) => u < 128)) {
          header(0x5, v.length);
          b.add(latin1.encode(v));
        } else {
          header(0x6, v.length);
          for (final u in v.codeUnits) {
            b.add([u >> 8, u & 0xff]);
          }
        }
      case List v:
        final refs = [for (final item in v) add(item)];
        header(0xa, refs.length);
        refs.forEach(ref);
      case Map v:
        final keys = [for (final k in v.keys) add('$k')];
        final values = [for (final item in v.values) add(item)];
        header(0xd, keys.length);
        keys.forEach(ref);
        values.forEach(ref);
      default:
        throw ArgumentError.value(value, 'value', 'Not a plist value');
    }
    objects[index] = b.takeBytes();
    return index;
  }

  add(root);
  if (objects.length > 0xffff) throw ArgumentError('Too many objects');
  out.add(latin1.encode('bplist00'));
  final offsets = <int>[];
  for (final o in objects) {
    offsets.add(out.length);
    out.add(o);
  }
  final table = out.length;
  for (final o in offsets) {
    out.add([o >> 24 & 0xff, o >> 16 & 0xff, o >> 8 & 0xff, o & 0xff]);
  }
  final trailer = ByteData(32)
    ..setUint8(6, 4)
    ..setUint8(7, 2)
    ..setUint64(8, objects.length)
    ..setUint64(16, 0)
    ..setUint64(24, table);
  out.add(trailer.buffer.asUint8List());
  return out.takeBytes();
}

/// The root object of an NSKeyedArchiver archive, references resolved:
/// strings, numbers and nested objects as plain values (to a depth).
Map<String, Object?> unarchiveRoot(Object? archive) {
  if (archive is! Map || archive[r'$objects'] is! List) {
    throw const FormatException('Not a keyed archive');
  }
  final objects = archive[r'$objects'] as List;
  final top = archive[r'$top'];
  final root = top is Map ? top['root'] : null;
  Object? resolve(Object? value, int depth) {
    if (depth > 16) return null;
    if (value is PlistUid) {
      if (value.value >= objects.length) return null;
      final o = objects[value.value];
      if (o == r'$null') return null;
      return resolve(o, depth + 1);
    }
    if (value is Map) {
      if (value['NS.string'] case final String s) return s;
      if (value['NS.objects'] case final List items
          when value['NS.keys'] == null) {
        return [for (final i in items) resolve(i, depth + 1)];
      }
      return {
        for (final MapEntry(:key, :value) in value.entries)
          if (key != r'$class') '$key': resolve(value, depth + 1),
      };
    }
    return value;
  }

  final resolved = resolve(root, 0);
  if (resolved is! Map<String, Object?>) {
    throw const FormatException('The archive has no root object');
  }
  return resolved;
}

/// An NSKeyedArchiver archive of one object of [className] with [fields]
/// (strings, numbers, booleans).
Uint8List archiveObject(String className, Map<String, Object> fields) {
  final objects = <Object>[r'$null'];
  final root = <String, Object>{};
  objects.add(root);
  root[r'$class'] = const PlistUid(2);
  objects.add({
    r'$classname': className,
    r'$classes': [className, 'NSObject'],
  });
  for (final MapEntry(:key, :value) in fields.entries) {
    if (value is String) {
      root[key] = PlistUid(objects.length);
      objects.add(value);
    } else {
      root[key] = value;
    }
  }
  return writeBinaryPlist({
    r'$version': 100000,
    r'$archiver': 'NSKeyedArchiver',
    r'$top': {'root': const PlistUid(1)},
    r'$objects': objects,
  });
}
