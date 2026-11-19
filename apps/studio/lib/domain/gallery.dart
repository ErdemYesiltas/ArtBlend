import 'document.dart';

/// Drawings kept together in the gallery (Procreate's stacks).
class GalleryStack {
  const GalleryStack({
    required this.id,
    required this.name,
    required this.members,
  });
  final String id, name;

  /// Drawing ids, in the stack's order.
  final List<String> members;

  GalleryStack copyWith({String? name, List<String>? members}) => GalleryStack(
    id: id,
    name: name ?? this.name,
    members: members ?? this.members,
  );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'members': members};
}

/// One top-level tile by id: an item, or a stack with its members that
/// exist, in its order.
typedef GalleryEntry = ({String id, GalleryStack? stack, List<String> members});

/// One tile of the gallery: a drawing or a stack.
sealed class GalleryItem {
  const GalleryItem();
  String get id;
}

class GalleryDrawing extends GalleryItem {
  const GalleryDrawing(this.document);
  final ArtDocument document;
  @override
  String get id => document.id;
}

class GalleryStackItem extends GalleryItem {
  const GalleryStackItem(this.stack, this.documents);
  final GalleryStack stack;

  /// The stack's drawings that exist, in its order.
  final List<ArtDocument> documents;
  @override
  String get id => stack.id;
}

/// The gallery's own order and stacks; drawings it does not know (new
/// ones) come first.
class GalleryLayout {
  GalleryLayout({
    List<String> order = const [],
    List<GalleryStack> stacks = const [],
  }) : order = List.unmodifiable(order),
       stacks = List.unmodifiable(stacks);

  /// Top-level drawing and stack ids, first to last.
  final List<String> order;
  final List<GalleryStack> stacks;

  Map<String, dynamic> toJson() => {
    'version': 1,
    'order': order,
    'stacks': [for (final s in stacks) s.toJson()],
  };

  /// Anything damaged is left out.
  factory GalleryLayout.fromJson(Object? json) {
    if (json is! Map) return GalleryLayout();
    List<String> ids(Object? list) => [
      if (list is List)
        for (final id in list)
          if (id is String) id,
    ];
    return GalleryLayout(
      order: ids(json['order']),
      stacks: [
        if (json['stacks'] case final List stacks)
          for (final s in stacks)
            if (s is Map && s['id'] is String && s['name'] is String)
              GalleryStack(
                id: s['id'] as String,
                name: s['name'] as String,
                members: ids(s['members']),
              ),
      ],
    );
  }

  GalleryStack? stackOf(String documentId) =>
      stacks.where((s) => s.members.contains(documentId)).firstOrNull;

  GalleryStack? stack(String id) => stacks.where((s) => s.id == id).firstOrNull;

  /// The top-level tiles for item [ids] (newest first): items it has not
  /// placed yet first, then its own order; stacks hold their members that
  /// exist. Shared by the gallery's drawings and the Theater's movies.
  List<GalleryEntry> entries(List<String> ids) {
    final known = ids.toSet();
    final stacked = <String>{};
    final stackEntries = <String, GalleryEntry>{};
    for (final s in stacks) {
      final members = [
        for (final id in s.members)
          if (known.contains(id) && stacked.add(id)) id,
      ];
      if (members.isNotEmpty) {
        stackEntries[s.id] = (id: s.id, stack: s, members: members);
      }
    }
    GalleryEntry single(String id) => (id: id, stack: null, members: const []);
    final placed = <String>{};
    final ordered = <GalleryEntry>[
      for (final id in order)
        if (stackEntries[id] case final stack? when placed.add(id))
          stack
        else if (known.contains(id) && !stacked.contains(id) && placed.add(id))
          single(id),
    ];
    return [
      for (final id in ids)
        if (!stacked.contains(id) && placed.add(id)) single(id),
      for (final stack in stackEntries.values)
        if (placed.add(stack.id)) stack,
      ...ordered,
    ];
  }

  /// The gallery's tiles for [documents] (newest first).
  List<GalleryItem> arrange(List<ArtDocument> documents) {
    final byId = {for (final d in documents) d.id: d};
    return [
      for (final e in entries([for (final d in documents) d.id]))
        if (e.stack case final stack?)
          GalleryStackItem(stack, [for (final m in e.members) byId[m]!])
        else
          GalleryDrawing(byId[e.id]!),
    ];
  }

  /// [ids] in the order the gallery shows them.
  GalleryLayout _withOrder(List<String> ids) =>
      GalleryLayout(order: ids, stacks: stacks);

  /// [id] moved just before [before] (the end when null), inside the stack
  /// that holds [before] when there is one, at the top level otherwise.
  GalleryLayout move(String id, String? before, List<String> ids) {
    if (id == before) return this;
    // Stacks stay at the top level.
    final into = before == null || stack(id) != null ? null : stackOf(before);
    if (into != null) {
      final members = [...into.members.where((m) => m != id)];
      members.insert(members.indexOf(before!), id);
      return _replaceStack(into.copyWith(members: members), leaving: id);
    }
    final top = [
      for (final item in entries(ids))
        if (item.id != id) item.id,
    ];
    final at = before == null ? -1 : top.indexOf(before);
    top.insert(at < 0 ? top.length : at, id);
    return GalleryLayout(
      order: top,
      stacks: [
        for (final s in stacks)
          s.copyWith(members: [...s.members.where((m) => m != id)]),
      ],
    );
  }

  GalleryLayout _replaceStack(GalleryStack next, {String? leaving}) =>
      GalleryLayout(
        order: order,
        stacks: [
          for (final s in stacks)
            if (s.id == next.id)
              next
            else
              s.copyWith(members: [...s.members.where((m) => m != leaving)]),
        ],
      );

  /// A new stack [id] of [ids] where the first of them was; [all] are
  /// every item's ids.
  GalleryLayout stackUp(
    String id,
    String name,
    List<String> ids,
    List<String> all,
  ) {
    if (ids.isEmpty) return this;
    final top = [for (final item in entries(all)) item.id];
    final at = top.indexWhere(ids.contains);
    final rest = [
      for (final s in stacks)
        s.copyWith(members: [...s.members.where((m) => !ids.contains(m))]),
    ];
    final next = [...top.where((i) => !ids.contains(i))];
    next.insert(at < 0 ? 0 : at.clamp(0, next.length), id);
    return GalleryLayout(
      order: next,
      stacks: [
        ...rest,
        GalleryStack(id: id, name: name, members: ids),
      ],
    );
  }

  /// [id] put at the end of stack [stackId].
  GalleryLayout addToStack(String id, String stackId) {
    final target = stack(stackId);
    if (target == null || target.members.contains(id)) return this;
    return _replaceStack(
      target.copyWith(members: [...target.members, id]),
      leaving: id,
    );
  }

  /// [id] taken out of its stack, right after it at the top level.
  GalleryLayout unstackDocument(String id, List<String> ids) {
    final from = stackOf(id);
    if (from == null) return this;
    final top = [for (final item in entries(ids)) item.id];
    final at = top.indexOf(from.id);
    top.insert(at + 1, id);
    return GalleryLayout(
      order: top,
      stacks: [
        for (final s in stacks)
          s.id == from.id
              ? s.copyWith(members: [...s.members.where((m) => m != id)])
              : s,
      ],
    );
  }

  /// The stack's drawings back at the top level, where it was.
  GalleryLayout dissolve(String stackId, List<String> ids) {
    final target = stack(stackId);
    if (target == null) return this;
    final top = [for (final item in entries(ids)) item.id];
    final at = top.indexOf(stackId);
    top
      ..removeAt(at < 0 ? 0 : at)
      ..insertAll(at < 0 ? 0 : at, target.members);
    return GalleryLayout(
      order: top,
      stacks: [...stacks.where((s) => s.id != stackId)],
    );
  }

  GalleryLayout renameStack(String stackId, String name) {
    final target = stack(stackId);
    return target == null ? this : _replaceStack(target.copyWith(name: name));
  }

  /// [copy] placed right after [of], in its stack if it has one.
  GalleryLayout placeCopy(String of, String copy, List<String> ids) {
    final from = stackOf(of);
    if (from != null) {
      final members = [...from.members];
      members.insert(members.indexOf(of) + 1, copy);
      return _replaceStack(from.copyWith(members: members));
    }
    final top = [for (final item in entries(ids)) item.id];
    top.insert(top.indexOf(of) + 1, copy);
    return _withOrder(top);
  }

  /// [ids] forgotten (deleted drawings).
  GalleryLayout without(Set<String> ids) => GalleryLayout(
    order: [...order.where((i) => !ids.contains(i))],
    stacks: [
      for (final s in stacks)
        s.copyWith(members: [...s.members.where((m) => !ids.contains(m))]),
    ],
  );
}
