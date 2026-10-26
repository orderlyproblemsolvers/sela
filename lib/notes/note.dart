class Note {
  Note({
    required this.id,
    this.title = '',
    this.preview = '',
    this.plain = '',
    this.pinned = false,
    this.archived = false,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.deletedAt,
    List<dynamic>? delta,
  })  : updatedAt = updatedAt ?? DateTime.now(),
        createdAt = createdAt ?? updatedAt ?? DateTime.now(),
        delta = delta ?? <dynamic>[];

  final String id;
  String title;

  /// Short excerpt shown on the card.
  String preview;

  /// Full plain text, used for search.
  String plain;

  bool pinned;
  bool archived;
  final DateTime createdAt;
  DateTime updatedAt;

  /// Set when the note is in the trash.
  DateTime? deletedAt;

  /// Quill document as Delta JSON (rich text + verse text).
  List<dynamic> delta;

  bool get isTrashed => deletedAt != null;

  String get displayTitle => title.trim().isEmpty ? 'Untitled' : title.trim();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'preview': preview,
        'plain': plain,
        'pinned': pinned,
        'archived': archived,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'deletedAt': deletedAt?.toIso8601String(),
        'delta': delta,
      };

  factory Note.fromJson(Map<String, dynamic> j) {
    final updated = DateTime.tryParse((j['updatedAt'] as String?) ?? '');
    return Note(
      id: j['id'] as String,
      title: (j['title'] as String?) ?? '',
      preview: (j['preview'] as String?) ?? '',
      plain: (j['plain'] as String?) ?? '',
      pinned: (j['pinned'] as bool?) ?? false,
      archived: (j['archived'] as bool?) ?? false,
      createdAt: DateTime.tryParse((j['createdAt'] as String?) ?? '') ?? updated,
      updatedAt: updated,
      deletedAt: DateTime.tryParse((j['deletedAt'] as String?) ?? ''),
      delta: (j['delta'] as List<dynamic>?) ?? <dynamic>[],
    );
  }
}
