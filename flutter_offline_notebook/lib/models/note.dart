class Note {
  const Note({
    required this.id,
    required this.title,
    required this.body,
    required this.category,
    required this.updatedAt,
    this.reminderAt,
    this.isPinned = false,
  });

  final String id;
  final String title;
  final String body;
  final String category;
  final DateTime updatedAt;
  final DateTime? reminderAt;
  final bool isPinned;

  int get notificationId {
    final parsedId = int.tryParse(id) ?? id.hashCode.abs();
    return parsedId % 2147483647;
  }

  Note copyWith({
    String? title,
    String? body,
    String? category,
    DateTime? updatedAt,
    DateTime? reminderAt,
    bool clearReminder = false,
    bool? isPinned,
  }) {
    return Note(
      id: id,
      title: title ?? this.title,
      body: body ?? this.body,
      category: category ?? this.category,
      updatedAt: updatedAt ?? this.updatedAt,
      reminderAt: clearReminder ? null : reminderAt ?? this.reminderAt,
      isPinned: isPinned ?? this.isPinned,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'category': category,
        'updatedAt': updatedAt.toIso8601String(),
        'reminderAt': reminderAt?.toIso8601String(),
        'isPinned': isPinned,
      };

  factory Note.fromJson(Map<String, dynamic> json) {
    return Note(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      category: json['category'] as String? ?? 'Личное',
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
      reminderAt: DateTime.tryParse(json['reminderAt'] as String? ?? ''),
      isPinned: json['isPinned'] as bool? ?? false,
    );
  }
}
