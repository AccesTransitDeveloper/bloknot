import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/note.dart';
import 'services/reminder_service.dart';

const _ink = Color(0xFF15243A);
const _muted = Color(0xFF7C8999);
const _canvas = Color(0xFFF3F6FA);
const _line = Color(0xFFE8EDF2);
const _teal = Color(0xFF18A999);
const _categories = ['Все', 'Рабочее', 'Личное', 'Идеи'];

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NotebookApp());
}

class NotebookApp extends StatelessWidget {
  const NotebookApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Офлайн-блокнот',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: _canvas,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _teal,
          primary: _teal,
          surface: Colors.white,
        ),
        fontFamily: 'Roboto',
        appBarTheme: const AppBarTheme(
          backgroundColor: _canvas,
          foregroundColor: _ink,
          elevation: 0,
          centerTitle: false,
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: _ink,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      home: const NotebookHome(),
    );
  }
}

class NotebookHome extends StatefulWidget {
  const NotebookHome({super.key});

  @override
  State<NotebookHome> createState() => _NotebookHomeState();
}

class _NotebookHomeState extends State<NotebookHome> {
  static const _storageKey = 'offline_notebook_notes_v1';
  List<Note> _notes = [];
  String _selectedCategory = 'Все';
  String _query = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNotes();
  }

  Future<void> _loadNotes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      final decoded = raw == null ? <dynamic>[] : jsonDecode(raw) as List;
      final loaded = decoded
          .map((item) => Note.fromJson(item as Map<String, dynamic>))
          .toList();
      if (!mounted) return;
      setState(() {
        _notes = _sortNotes(loaded);
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showMessage('Не удалось загрузить заметки: $error');
    }
  }

  List<Note> _sortNotes(List<Note> items) {
    items.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return items;
  }

  Future<void> _persistNotes(List<Note> notes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode(notes.map((note) => note.toJson()).toList()),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _checkNotifications() async {
    try {
      await ReminderService.instance.showTestNotification();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Проверка уведомлений'),
          content: const Text(
            'Отправлено тестовое уведомление. Проверьте шторку уведомлений.\n\n'
            'Если его нет: Настройки телефона → Приложения → Офлайн-блокнот → '
            'Уведомления → включите уведомления и канал «Напоминания».\n\n'
            'Для проверки времени создайте заметку с напоминанием через 2 минуты '
            'и сверните приложение. Интернет не нужен. Разрешите «Будильники и '
            'напоминания» и фоновую работу в настройках телефона.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Понятно'),
            ),
          ],
        ),
      );
    } catch (error) {
      await _showReminderError('$error');
    }
  }

  Future<void> _showReminderError(String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Уведомление не настроено'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Понятно'),
          ),
        ],
      ),
    );
  }

  List<Note> get _visibleNotes {
    final normalizedQuery = _query.trim().toLowerCase();
    return _notes.where((note) {
      final matchesCategory =
          _selectedCategory == 'Все' || note.category == _selectedCategory;
      final matchesQuery = normalizedQuery.isEmpty ||
          note.title.toLowerCase().contains(normalizedQuery) ||
          note.body.toLowerCase().contains(normalizedQuery);
      return matchesCategory && matchesQuery;
    }).toList();
  }

  Future<void> _openEditor({Note? note}) async {
    final result = await showModalBottomSheet<Note>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => NoteEditor(note: note),
    );
    if (result == null) return;

    Note? existing;
    for (final item in _notes) {
      if (item.id == result.id) {
        existing = item;
        break;
      }
    }
    final next = _sortNotes([
      ..._notes.where((item) => item.id != result.id),
      result,
    ]);

    try {
      if (existing?.reminderAt != null &&
          existing!.reminderAt != result.reminderAt) {
        await ReminderService.instance.cancel(existing.notificationId);
      }
      var exactReminder = true;
      if (result.reminderAt != null) {
        exactReminder = await ReminderService.instance.schedule(
          id: result.notificationId,
          title: result.title,
          body: result.body,
          at: result.reminderAt!,
        );
      }
      await _persistNotes(next);
      if (!mounted) return;
      setState(() => _notes = next);
      _showMessage(
        result.reminderAt == null
            ? 'Заметка сохранена на устройстве'
            : exactReminder
                ? 'Заметка и напоминание сохранены'
                : 'Напоминание сохранено. Без разрешения на точные будильники '
                    'Android может значительно задержать уведомление.',
      );
    } catch (error) {
      // Do not display a reminder as active when scheduling failed.
      final withoutReminder = [
        for (final item in next)
          if (item.id == result.id)
            item.copyWith(clearReminder: true)
          else
            item,
      ];
      await _persistNotes(withoutReminder);
      if (!mounted) return;
      setState(() => _notes = withoutReminder);
      await _showReminderError(
        'Заметка сохранена, но напоминание не установлено.\n\n$error\n\n'
        'Проверьте разрешения уведомлений и Android-файлы по инструкции '
        'ANDROID_SETUP.md, затем снова установите время в заметке.',
      );
    }
  }

  Future<void> _togglePin(Note note) async {
    final updated = note.copyWith(isPinned: !note.isPinned);
    final next = _sortNotes([
      for (final item in _notes) if (item.id == note.id) updated else item,
    ]);
    await _persistNotes(next);
    if (!mounted) return;
    setState(() => _notes = next);
  }

  Future<void> _deleteNote(Note note) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить заметку?'),
        content: const Text('Это действие нельзя отменить.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFD94F55)),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (shouldDelete != true) return;

    await ReminderService.instance.cancel(note.notificationId);
    final next = _notes.where((item) => item.id != note.id).toList();
    await _persistNotes(next);
    if (!mounted) return;
    setState(() => _notes = next);
    _showMessage('Заметка удалена');
  }

  @override
  Widget build(BuildContext context) {
    final remindersCount =
        _notes.where((note) => note.reminderAt?.isAfter(DateTime.now()) ?? false).length;

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _TopBar(totalNotes: _notes.length),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _checkNotifications,
                        icon: const Icon(Icons.notifications_outlined),
                        label: const Text('Проверить уведомления'),
                      ),
                    ),
                    const SizedBox(height: 26),
                    const Text(
                      'Ваш рабочий\nблокнот',
                      style: TextStyle(
                        color: _ink,
                        fontSize: 30,
                        height: 1.12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.7,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Все записи доступны даже без сети',
                      style: TextStyle(fontSize: 14, color: _muted),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: _SummaryCard(
                            icon: Icons.description_outlined,
                            label: 'ЗАМЕТОК',
                            value: '${_notes.length}',
                            color: const Color(0xFF4267A9),
                            background: const Color(0xFFEAF0FA),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _SummaryCard(
                            icon: Icons.notifications_none_rounded,
                            label: 'НАПОМИНАНИЙ',
                            value: '$remindersCount',
                            color: const Color(0xFF138D7F),
                            background: const Color(0xFFE5F5F2),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    _SearchField(
                      onChanged: (value) => setState(() => _query = value),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      height: 40,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _categories.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final category = _categories[index];
                          final selected = category == _selectedCategory;
                          return ChoiceChip(
                            label: Text(category),
                            selected: selected,
                            showCheckmark: false,
                            onSelected: (_) =>
                                setState(() => _selectedCategory = category),
                            labelStyle: TextStyle(
                              color: selected ? Colors.white : _muted,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                            backgroundColor: Colors.white,
                            selectedColor: _ink,
                            side: BorderSide(
                              color: selected ? _ink : _line,
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(13),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 22),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text(
                          'Последние записи',
                          style: TextStyle(
                            color: _ink,
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          '${_visibleNotes.length} ${_noteWord(_visibleNotes.length)}',
                          style: const TextStyle(
                            color: _muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
            if (_isLoading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: CircularProgressIndicator(color: _teal),
                ),
              )
            else if (_visibleNotes.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyState(
                  hasNotes: _notes.isNotEmpty,
                  onCreate: () => _openEditor(),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 110),
                sliver: SliverList.separated(
                  itemCount: _visibleNotes.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 11),
                  itemBuilder: (context, index) {
                    final note = _visibleNotes[index];
                    return NoteCard(
                      note: note,
                      onTap: () => _openEditor(note: note),
                      onPin: () => _togglePin(note),
                      onDelete: () => _deleteNote(note),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        backgroundColor: _ink,
        foregroundColor: Colors.white,
        elevation: 4,
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'Новая заметка',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  String _noteWord(int count) {
    if (count % 10 == 1 && count % 100 != 11) return 'запись';
    if ([2, 3, 4].contains(count % 10) &&
        ![12, 13, 14].contains(count % 100)) {
      return 'записи';
    }
    return 'записей';
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.totalNotes});

  final int totalNotes;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _ink,
            borderRadius: BorderRadius.circular(15),
          ),
          child: const Icon(
            Icons.menu_book_rounded,
            color: Colors.white,
            size: 23,
          ),
        ),
        const SizedBox(width: 11),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'NOTEBOOK',
                style: TextStyle(
                  color: _ink,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                  fontSize: 13,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'ЛИЧНОЕ ПРОСТРАНСТВО',
                style: TextStyle(
                  color: _muted,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                  fontSize: 9,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFFE6F5F1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off_rounded, size: 13, color: _teal),
              SizedBox(width: 5),
              Text(
                'ОФЛАЙН',
                style: TextStyle(
                  color: Color(0xFF138D7F),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.background,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _line),
      ),
      child: Row(
        children: [
          Container(
            height: 38,
            width: 38,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 19,
                    height: 1,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _muted,
                    letterSpacing: 0.35,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      onChanged: onChanged,
      style: const TextStyle(color: _ink, fontSize: 14),
      decoration: InputDecoration(
        hintText: 'Поиск по заметкам',
        hintStyle: const TextStyle(color: _muted, fontSize: 14),
        prefixIcon: const Icon(Icons.search_rounded, color: _muted, size: 21),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: _line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: _line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: _teal, width: 1.4),
        ),
      ),
    );
  }
}

class NoteCard extends StatelessWidget {
  const NoteCard({
    required this.note,
    required this.onTap,
    required this.onPin,
    required this.onDelete,
  });

  final Note note;
  final VoidCallback onTap;
  final VoidCallback onPin;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final accent = _categoryColor(note.category);
    final reminder = note.reminderAt;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(15, 14, 9, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _line),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 4,
                height: 62,
                margin: const EdgeInsets.only(top: 2, right: 12),
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            note.title.isEmpty ? 'Без названия' : note.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _ink,
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        if (note.isPinned)
                          const Padding(
                            padding: EdgeInsets.only(left: 5),
                            child: Icon(
                              Icons.push_pin_rounded,
                              color: _teal,
                              size: 15,
                            ),
                          ),
                      ],
                    ),
                    if (note.body.trim().isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        note.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF69778A),
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 7,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _SmallTag(label: note.category, color: accent),
                        Text(
                          _formatDate(note.updatedAt),
                          style: const TextStyle(
                            color: _muted,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (reminder != null && reminder.isAfter(DateTime.now()))
                          _ReminderTag(at: reminder),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Действия с заметкой',
                icon: const Icon(Icons.more_horiz_rounded, color: _muted),
                onSelected: (value) {
                  if (value == 'pin') onPin();
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'pin',
                    child: Row(
                      children: [
                        Icon(note.isPinned
                            ? Icons.push_pin_outlined
                            : Icons.push_pin_rounded),
                        const SizedBox(width: 10),
                        Text(note.isPinned ? 'Открепить' : 'Закрепить'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline_rounded, color: Color(0xFFD94F55)),
                        SizedBox(width: 10),
                        Text('Удалить'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SmallTag extends StatelessWidget {
  const _SmallTag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ReminderTag extends StatelessWidget {
  const _ReminderTag({required this.at});

  final DateTime at;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.notifications_active_outlined, size: 11, color: _teal),
        const SizedBox(width: 3),
        Text(
          _formatReminder(at),
          style: const TextStyle(
            color: _teal,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasNotes, required this.onCreate});

  final bool hasNotes;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              height: 68,
              width: 68,
              decoration: BoxDecoration(
                color: const Color(0xFFE5F5F2),
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Icon(
                Icons.note_alt_outlined,
                color: _teal,
                size: 30,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              hasNotes ? 'Ничего не найдено' : 'Здесь появятся ваши заметки',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _ink,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              hasNotes
                  ? 'Измените поиск или выберите другую категорию.'
                  : 'Создайте первую запись — она сохранится на телефоне.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: _muted, fontSize: 13, height: 1.5),
            ),
            if (!hasNotes) ...[
              const SizedBox(height: 17),
              OutlinedButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Создать заметку'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class NoteEditor extends StatefulWidget {
  const NoteEditor({super.key, this.note});

  final Note? note;

  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
  late String _category;
  DateTime? _reminderAt;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.note?.title ?? '');
    _bodyController = TextEditingController(text: widget.note?.body ?? '');
    _category = widget.note?.category ?? 'Рабочее';
    _reminderAt = widget.note?.reminderAt;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _pickReminder() async {
    final now = DateTime.now();
    final initial = _reminderAt ?? now.add(const Duration(hours: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(now) ? now : initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 5),
      helpText: 'Выберите дату напоминания',
      cancelText: 'Отмена',
      confirmText: 'Далее',
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      helpText: 'Выберите время',
      cancelText: 'Отмена',
      confirmText: 'Готово',
    );
    if (time == null || !mounted) return;
    final picked = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (picked.isBefore(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Выберите время в будущем.')),
      );
      return;
    }
    setState(() => _reminderAt = picked);
  }

  void _save() {
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();
    if (title.isEmpty && body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Добавьте заголовок или текст заметки.')),
      );
      return;
    }

    final original = widget.note;
    final note = Note(
      id: original?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      body: body,
      category: _category,
      updatedAt: DateTime.now(),
      reminderAt: _reminderAt,
      isPinned: original?.isPinned ?? false,
    );
    HapticFeedback.selectionClick();
    Navigator.of(context).pop(note);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.92,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCE3EA),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.note == null ? 'Новая заметка' : 'Редактировать',
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Закрыть',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: _muted),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _EditorField(
                controller: _titleController,
                hint: 'Заголовок',
                maxLines: 1,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 10),
              _EditorField(
                controller: _bodyController,
                hint: 'Напишите что-нибудь важное…',
                maxLines: 6,
                minLines: 4,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 17),
              const Text(
                'КАТЕГОРИЯ',
                style: TextStyle(
                  color: _muted,
                  letterSpacing: 0.8,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 9),
              Wrap(
                spacing: 8,
                children: _categories.skip(1).map((category) {
                  final selected = _category == category;
                  final color = _categoryColor(category);
                  return ChoiceChip(
                    label: Text(category),
                    selected: selected,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _category = category),
                    selectedColor: color.withValues(alpha: 0.13),
                    backgroundColor: _canvas,
                    side: BorderSide(
                      color: selected ? color.withValues(alpha: 0.35) : _line,
                    ),
                    labelStyle: TextStyle(
                      color: selected ? color : _muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 18),
              InkWell(
                onTap: _pickReminder,
                borderRadius: BorderRadius.circular(15),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _reminderAt == null
                        ? const Color(0xFFF7F9FB)
                        : const Color(0xFFE9F7F4),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(
                      color: _reminderAt == null
                          ? _line
                          : const Color(0xFFC7E9E2),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.notifications_active_outlined,
                        color: _teal,
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _reminderAt == null
                                  ? 'Напомнить позже'
                                  : _formatReminder(_reminderAt!),
                              style: const TextStyle(
                                color: _ink,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            const Text(
                              'Сработает без интернета',
                              style: TextStyle(color: _muted, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      if (_reminderAt != null)
                        IconButton(
                          tooltip: 'Убрать напоминание',
                          onPressed: () => setState(() => _reminderAt = null),
                          icon: const Icon(
                            Icons.close_rounded,
                            color: _muted,
                            size: 19,
                          ),
                        )
                      else
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: _muted,
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: _ink,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  icon: const Icon(Icons.check_rounded, size: 19),
                  label: const Text(
                    'Сохранить заметку',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditorField extends StatelessWidget {
  const _EditorField({
    required this.controller,
    required this.hint,
    required this.maxLines,
    this.minLines,
    required this.textCapitalization,
  });

  final TextEditingController controller;
  final String hint;
  final int maxLines;
  final int? minLines;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      minLines: minLines,
      textCapitalization: textCapitalization,
      style: const TextStyle(color: _ink, fontSize: 14, height: 1.5),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFFA1ACB8), fontSize: 14),
        filled: true,
        fillColor: const Color(0xFFF7F9FB),
        contentPadding: const EdgeInsets.all(14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _teal, width: 1.3),
        ),
      ),
    );
  }
}

Color _categoryColor(String category) {
  switch (category) {
    case 'Рабочее':
      return const Color(0xFF4774B8);
    case 'Личное':
      return const Color(0xFFB07C43);
    case 'Идеи':
      return const Color(0xFF8B69B0);
    default:
      return _teal;
  }
}

String _formatDate(DateTime date) {
  final local = date.toLocal();
  final now = DateTime.now();
  if (local.year == now.year && local.month == now.month && local.day == now.day) {
    return 'Сегодня, ${_twoDigits(local.hour)}:${_twoDigits(local.minute)}';
  }
  return '${_twoDigits(local.day)}.${_twoDigits(local.month)}.${local.year}';
}

String _formatReminder(DateTime date) {
  final local = date.toLocal();
  return '${_twoDigits(local.day)}.${_twoDigits(local.month)}.${local.year} в '
      '${_twoDigits(local.hour)}:${_twoDigits(local.minute)}';
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');
