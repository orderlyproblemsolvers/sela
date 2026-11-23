class Note {
  Note({
    required this.id,
    this.title = '',
    this.preview = '',
    this.plain = '',
    this.pinned = false,
    this.archived = false,
    this.pinOrder = 0,
    this.folderId,
    List<String>? tags,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.deletedAt,
    List<dynamic>? delta,
  })  : updatedAt = updatedAt ?? DateTime.now(),
        createdAt = createdAt ?? updatedAt ?? DateTime.now(),
        tags = tags ?? extractTags('$title\n$plain'),
        delta = delta ?? <dynamic>[];

  final String id;
  String title;
  String preview;
  String plain;
  bool pinned;
  bool archived;
  int pinOrder;
  String? folderId;
  List<String> tags;
  final DateTime createdAt;
  DateTime updatedAt;
  DateTime? deletedAt;
  List<dynamic> delta;

  bool get isTrashed => deletedAt != null;
  String get displayTitle => title.trim().isEmpty ? 'Untitled' : title.trim();

  static final RegExp _tagRegex = RegExp(r'(?:^|\s)#([a-zA-Z0-9_-]{2,30})\b');

  static List<String> extractTags(String text) {
    final matches = _tagRegex.allMatches(text);
    final set = <String>{};
    for (final m in matches) {
      final t = m.group(1)?.toLowerCase();
      if (t != null && t.isNotEmpty) set.add(t);
    }
    return set.toList()..sort();
  }

  void refreshTags() {
    tags = extractTags('$title\n$plain');
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'preview': preview,
        'plain': plain,
        'pinned': pinned,
        'archived': archived,
        'pinOrder': pinOrder,
        'folderId': folderId,
        'tags': tags,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'deletedAt': deletedAt?.toIso8601String(),
        'delta': delta,
      };

  factory Note.fromJson(Map<String, dynamic> j) {
    final updated = DateTime.tryParse((j['updatedAt'] as String?) ?? '');
    final title = (j['title'] as String?) ?? '';
    final plain = (j['plain'] as String?) ?? '';
    final rawTags = (j['tags'] as List<dynamic>?)?.cast<String>();
    return Note(
      id: j['id'] as String,
      title: title,
      preview: (j['preview'] as String?) ?? '',
      plain: plain,
      pinned: (j['pinned'] as bool?) ?? false,
      archived: (j['archived'] as bool?) ?? false,
      pinOrder: (j['pinOrder'] as int?) ?? 0,
      folderId: j['folderId'] as String?,
      tags: rawTags ?? extractTags('$title\n$plain'),
      createdAt: DateTime.tryParse((j['createdAt'] as String?) ?? '') ?? updated,
      updatedAt: updated,
      deletedAt: DateTime.tryParse((j['deletedAt'] as String?) ?? ''),
      delta: (j['delta'] as List<dynamic>?) ?? <dynamic>[],
    );
  }
}

class NoteFolder {
  NoteFolder({
    required this.id,
    required this.name,
    DateTime? createdAt,
    this.deletedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  String name;
  final DateTime createdAt;
  DateTime? deletedAt;

  bool get isTrashed => deletedAt != null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'deletedAt': deletedAt?.toIso8601String(),
      };

  factory NoteFolder.fromJson(Map<String, dynamic> json) => NoteFolder(
        id: json['id'] as String,
        name: json['name'] as String,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
        deletedAt: DateTime.tryParse(json['deletedAt'] as String? ?? ''),
      );
}