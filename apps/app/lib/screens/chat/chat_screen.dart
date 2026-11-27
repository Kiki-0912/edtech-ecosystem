import 'dart:async';

import 'package:edtech_app/auth/auth_provider.dart';
import 'package:edtech_app/formats.dart';
import 'package:edtech_app/models/channel.dart';
import 'package:edtech_app/models/chat_message.dart';
import 'package:edtech_app/models/course.dart';
import 'package:edtech_app/screens/home/home_data.dart' show myCourses;
import 'package:edtech_app/services/api_service.dart';
import 'package:edtech_app/ui/ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// Course channels. Pick a course, then a channel; messages refresh every
/// 15 seconds while the screen is open.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, this.initialCourseId});

  final String? initialCourseId;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _composer = TextEditingController();
  final _scroll = ScrollController();
  Timer? _poll;

  List<Course> _courses = const [];
  String? _courseId;
  List<Channel> _channels = const [];
  String? _channelId;
  List<ChatMessage> _messages = const [];
  Map<String, String> _names = const {};

  bool _loading = true;
  bool _loadingMessages = false;
  Object? _error;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _courseId = widget.initialCourseId;
    _load();
    _poll = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _refreshMessages(),
    );
  }

  @override
  void didUpdateWidget(ChatScreen old) {
    super.didUpdateWidget(old);
    final id = widget.initialCourseId;
    if (id != null && id != old.initialCourseId && id != _courseId) {
      _selectCourse(id);
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final user = context.read<AuthProvider>().user;
    if (user == null) return;
    final api = ApiService.instance;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        api.getCourses(),
        api.getStudents().catchError((_) => <Map<String, dynamic>>[]),
      ]);
      final courses = myCourses(user, results[0] as List<Course>);
      final names = <String, String>{
        for (final s in results[1] as List<Map<String, dynamic>>)
          s['id'].toString(): s['displayName']?.toString() ?? 'Student',
        for (final c in courses)
          if (c.teacherName != null) c.teacherId: c.teacherName!,
        user.id: user.displayName,
      };
      if (!mounted) return;
      setState(() {
        _courses = courses;
        _names = names;
        _loading = false;
        if (_courseId == null || !courses.any((c) => c.id == _courseId)) {
          _courseId = courses.isEmpty ? null : courses.first.id;
        }
      });
      if (_courseId != null) await _loadChannels();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _selectCourse(String id) async {
    setState(() {
      _courseId = id;
      _channelId = null;
      _channels = const [];
      _messages = const [];
    });
    await _loadChannels();
  }

  Future<void> _loadChannels() async {
    final courseId = _courseId;
    if (courseId == null) return;
    try {
      final channels = await ApiService.instance.getChannels(courseId);
      if (!mounted || courseId != _courseId) return;
      setState(() {
        _channels = channels;
        // Default to the discussion channel rather than announcements.
        _channelId = channels
                .where((c) => !c.isAnnouncement)
                .map((c) => c.id)
                .firstOrNull ??
            channels.firstOrNull?.id;
      });
      await _loadMessages();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _selectChannel(String id) async {
    setState(() {
      _channelId = id;
      _messages = const [];
    });
    await _loadMessages();
  }

  Future<void> _loadMessages() async {
    final channelId = _channelId;
    if (channelId == null) return;
    setState(() => _loadingMessages = true);
    await _refreshMessages();
    if (mounted) setState(() => _loadingMessages = false);
  }

  Future<void> _refreshMessages() async {
    final channelId = _channelId;
    if (channelId == null || _sending) return;
    try {
      final messages = await ApiService.instance.getMessages(channelId);
      if (!mounted || channelId != _channelId) return;
      final grew = messages.length != _messages.length;
      setState(() {
        _messages = messages..sort((a, b) => a.sentAt.compareTo(b.sentAt));
      });
      if (grew) _scrollToEnd();
    } catch (_) {
      // Polling failures are silent; the next tick retries.
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Channel? get _channel =>
      _channels.where((c) => c.id == _channelId).firstOrNull;

  bool _canPost(Channel? channel) {
    final user = context.read<AuthProvider>().user;
    if (channel == null || user == null) return false;
    return !(channel.isAnnouncement && user.isStudent);
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _composer.text).trim();
    final user = context.read<AuthProvider>().user;
    final channelId = _channelId;
    if (text.isEmpty || user == null || channelId == null || _sending) return;

    final optimistic = ChatMessage(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      channelId: channelId,
      authorId: user.id,
      body: text,
      sentAt: DateTime.now(),
    );
    setState(() {
      _sending = true;
      _messages = [..._messages, optimistic];
    });
    _composer.clear();
    _scrollToEnd();
    try {
      final saved = await ApiService.instance.postMessage(
        channelId: channelId,
        authorId: user.id,
        body: text,
      );
      if (!mounted) return;
      setState(() {
        _messages = [
          for (final m in _messages) m.id == optimistic.id ? saved : m,
        ];
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages = _messages.where((m) => m.id != optimistic.id).toList();
      });
      _composer.text = text;
      showToast(
        context,
        'Message not sent: ${friendlyError(e)}',
        kind: ToastKind.error,
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final wide = MediaQuery.sizeOf(context).width >= Breakpoints.expanded;

    if (_loading || _error != null || _courses.isEmpty) {
      return AppPage(
        title: 'Chat',
        subtitle: 'Talk with your classes',
        children: [
          AsyncBody(
            loading: _loading,
            error: _error,
            onRetry: _load,
            isEmpty: _courses.isEmpty,
            empty: const EmptyState(
              icon: Icons.forum_outlined,
              title: 'No class chats yet',
              message: 'Join a course to chat with your class.',
            ),
            builder: (_) => const SizedBox.shrink(),
          ),
        ],
      );
    }

    final coursePicker = DropdownButtonFormField<String>(
      key: const Key('chat-course'),
      initialValue: _courseId,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Course',
        prefixIcon: Icon(Icons.menu_book_outlined, size: 20),
        isDense: true,
      ),
      items: [
        for (final course in _courses)
          DropdownMenuItem(
            value: course.id,
            child: Text(
              '${course.code} · ${course.title}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (v) {
        if (v != null && v != _courseId) _selectCourse(v);
      },
    );

    final conversation = _Conversation(
      channel: _channel,
      messages: _messages,
      names: _names,
      loading: _loadingMessages,
      scroll: _scroll,
      composer: _composer,
      canPost: _canPost(_channel),
      sending: _sending,
      onSend: _send,
    );

    if (wide) {
      return ColoredBox(
        color: c.background,
        child: Row(
          children: [
            Container(
              width: 300,
              decoration: BoxDecoration(
                color: c.surface,
                border: Border(right: BorderSide(color: c.border)),
              ),
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  coursePicker,
                  const SizedBox(height: AppSpacing.md),
                  Text('CHANNELS', style: context.text.labelSmall),
                  const SizedBox(height: AppSpacing.xs),
                  for (final ch in _channels)
                    _ChannelTile(
                      channel: ch,
                      selected: ch.id == _channelId,
                      onTap: () => _selectChannel(ch.id),
                    ),
                ],
              ),
            ),
            Expanded(child: conversation),
          ],
        ),
      );
    }

    return ColoredBox(
      color: c.background,
      child: Column(
        children: [
          Container(
            color: c.surface,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                coursePicker,
                const SizedBox(height: AppSpacing.xs),
                FilterChips<String?>(
                  options: [
                    for (final ch in _channels)
                      FilterOption(
                        ch.id,
                        ch.isAnnouncement ? ch.name : '# ${ch.name}',
                      ),
                  ],
                  selected: _channelId,
                  onSelected: (id) {
                    if (id != null) _selectChannel(id);
                  },
                ),
              ],
            ),
          ),
          Divider(height: 1, color: c.border),
          Expanded(child: conversation),
        ],
      ),
    );
  }
}

class _ChannelTile extends StatelessWidget {
  const _ChannelTile({
    required this.channel,
    required this.selected,
    required this.onTap,
  });

  final Channel channel;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: selected ? c.accentSoft : c.surface,
      borderRadius: AppRadius.mdAll,
      child: InkWell(
        key: Key('channel-${channel.id}'),
        borderRadius: AppRadius.mdAll,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              Icon(
                channel.isAnnouncement
                    ? Icons.campaign_outlined
                    : Icons.tag_rounded,
                size: 18,
                color: selected ? c.accentText : c.textMuted,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  channel.name,
                  style: context.text.labelLarge?.copyWith(
                    color: selected ? c.accentText : c.textSecondary,
                  ),
                ),
              ),
              if (channel.isAnnouncement)
                const StatusBadge(label: 'Staff only', tone: Tone.info),
            ],
          ),
        ),
      ),
    );
  }
}

class _Conversation extends StatelessWidget {
  const _Conversation({
    required this.channel,
    required this.messages,
    required this.names,
    required this.loading,
    required this.scroll,
    required this.composer,
    required this.canPost,
    required this.sending,
    required this.onSend,
  });

  final Channel? channel;
  final List<ChatMessage> messages;
  final Map<String, String> names;
  final bool loading;
  final ScrollController scroll;
  final TextEditingController composer;
  final bool canPost;
  final bool sending;
  final Future<void> Function([String? preset]) onSend;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final me = context.watch<AuthProvider>().user?.id;

    Widget body;
    if (loading) {
      body = const Padding(
        padding: EdgeInsets.all(AppSpacing.md),
        child: SkeletonList(count: 4, itemHeight: 48),
      );
    } else if (messages.isEmpty) {
      body = Center(
        child: SingleChildScrollView(
          child: EmptyState(
            icon: Icons.forum_outlined,
            title: 'Start the conversation',
            message: canPost
                ? 'Say hello to your class.'
                : 'Announcements from your teachers will appear here.',
            action: canPost
                ? Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final starter in const [
                        'Hi everyone 👋',
                        'Any questions about the assignment?',
                      ])
                        ActionChip(
                          label: Text(starter),
                          onPressed: () => onSend(starter),
                        ),
                    ],
                  )
                : null,
          ),
        ),
      );
    } else {
      body = ListView.builder(
        controller: scroll,
        padding: const EdgeInsets.all(AppSpacing.md),
        itemCount: messages.length,
        itemBuilder: (context, i) {
          final m = messages[i];
          final prev = i > 0 ? messages[i - 1] : null;
          final newDay = prev == null || !isSameDay(prev.sentAt, m.sentAt);
          final grouped = !newDay &&
              prev.authorId == m.authorId &&
              m.sentAt.difference(prev.sentAt).inMinutes < 5;
          return Column(
            children: [
              if (newDay) _DateDivider(date: m.sentAt),
              _Bubble(
                message: m,
                author: names[m.authorId] ?? 'Member',
                own: m.authorId == me,
                showAuthor: !grouped,
                pending: m.id.startsWith('local-'),
              ),
            ],
          );
        },
      );
    }

    return Column(
      children: [
        if (channel != null)
          Container(
            width: double.infinity,
            color: c.surface,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                Icon(
                  channel!.isAnnouncement
                      ? Icons.campaign_outlined
                      : Icons.tag_rounded,
                  size: 20,
                  color: c.textMuted,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(channel!.name, style: context.text.titleMedium),
                ),
                Text(
                  '${channel!.memberIds.length} members',
                  style: context.text.bodySmall,
                ),
              ],
            ),
          ),
        Divider(height: 1, color: c.border),
        Expanded(child: body),
        Divider(height: 1, color: c.border),
        Container(
          color: c.surface,
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: SafeArea(
            top: false,
            child: canPost
                ? Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('chat-input'),
                          controller: composer,
                          minLines: 1,
                          maxLines: 4,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => onSend(),
                          decoration: InputDecoration(
                            hintText: channel == null
                                ? 'Message'
                                : 'Message #${channel!.name}',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      IconButton.filled(
                        key: const Key('chat-send'),
                        tooltip: 'Send',
                        onPressed: sending ? null : () => onSend(),
                        icon: const Icon(Icons.arrow_upward_rounded),
                      ),
                    ],
                  )
                : Padding(
                    padding: const EdgeInsets.all(AppSpacing.xs),
                    child: Row(
                      children: [
                        Icon(
                          Icons.lock_outline_rounded,
                          size: 18,
                          color: c.textMuted,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(
                            'Only teachers and admins can post announcements.',
                            style: context.text.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _DateDivider extends StatelessWidget {
  const _DateDivider({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final label = isSameDay(date, now)
        ? 'Today'
        : isSameDay(date, now.subtract(const Duration(days: 1)))
            ? 'Yesterday'
            : shortDate(date);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Text(label, style: context.text.labelSmall),
          ),
          const Expanded(child: Divider()),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.author,
    required this.own,
    required this.showAuthor,
    required this.pending,
  });

  final ChatMessage message;
  final String author;
  final bool own;
  final bool showAuthor;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bubble = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: own ? c.accent : c.surface,
          border: own ? null : Border.all(color: c.border),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(AppRadius.lg),
            topRight: const Radius.circular(AppRadius.lg),
            bottomLeft: Radius.circular(own ? AppRadius.lg : AppRadius.sm / 2),
            bottomRight: Radius.circular(own ? AppRadius.sm / 2 : AppRadius.lg),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.body,
              style: context.text.bodyMedium?.copyWith(
                color: own ? c.onAccent : c.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              pending ? 'Sending…' : clockTime(message.sentAt),
              style: context.text.bodySmall?.copyWith(
                color: own ? c.onAccent.withValues(alpha: 0.7) : c.textMuted,
              ),
            ),
          ],
        ),
      ),
    );

    return Padding(
      padding: EdgeInsets.only(top: showAuthor ? AppSpacing.sm : 2),
      child: Row(
        mainAxisAlignment:
            own ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!own)
            SizedBox(
              width: 40,
              child: showAuthor ? Avatar(name: author, size: 32) : null,
            ),
          Flexible(
            child: Column(
              crossAxisAlignment:
                  own ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (showAuthor && !own)
                  Padding(
                    padding: const EdgeInsets.only(
                      left: AppSpacing.xxs,
                      bottom: 2,
                    ),
                    child: Text(author, style: context.text.labelMedium),
                  ),
                bubble,
              ],
            ),
          ),
        ],
      ),
    );
  }
}
