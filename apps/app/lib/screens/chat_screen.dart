import 'package:edtech_app/auth/auth_provider.dart';
import 'package:edtech_app/models/channel.dart';
import 'package:edtech_app/models/chat_message.dart';
import 'package:edtech_app/services/api_service.dart';
import 'package:edtech_app/theme.dart';
import 'package:edtech_app/widgets/bounce_tap.dart';
import 'package:edtech_app/widgets/message_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// NOIR FLAME — "Signal" Messenger
/// Real-time feel with optimistic sending, `#channel` pills, and flame micro-interactions.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  List<Channel> _channels = [];
  Channel? _selected;
  List<ChatMessage> _messages = [];
  bool _loading = false;
  String? _error;
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadChannels();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadChannels() async {
    setState(() => _loading = true);
    try {
      _channels = await ApiService.instance.getChannels('c-001');
      if (_channels.isNotEmpty) {
        await _selectChannel(_channels.first);
      } else {
        if (mounted) setState(() => _loading = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _selectChannel(Channel channel) async {
    setState(() {
      _selected = channel;
      _messages = [];
      _loading = true;
      _error = null;
    });
    try {
      final msgs = await ApiService.instance.getMessages(channel.id);
      if (!mounted) return;
      setState(() {
        _messages = msgs;
        _loading = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  /// Optimistic message send: instant UI response, background sync.
  Future<void> _sendMessage([String? quickText]) async {
    final body = (quickText ?? _controller.text).trim();
    final userId = context.read<AuthProvider>().user?.id;
    if (body.isEmpty || _selected == null || userId == null) return;

    HapticFeedback.lightImpact();
    if (quickText == null) _controller.clear();

    // 1. Optimistic insert
    final optimisticMessage = ChatMessage(
      id: 'temp-${DateTime.now().millisecondsSinceEpoch}',
      channelId: _selected!.id,
      authorId: userId,
      body: body,
      sentAt: DateTime.now(),
    );

    setState(() {
      _messages.add(optimisticMessage);
    });
    _scrollToBottom();

    // 2. Network delivery
    try {
      final savedMessage = await ApiService.instance.postMessage(
        channelId: _selected!.id,
        authorId: userId,
        body: body,
      );
      if (!mounted) return;
      setState(() {
        final idx = _messages.indexWhere((m) => m.id == optimisticMessage.id);
        if (idx != -1) {
          _messages[idx] = savedMessage;
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _messages.removeWhere((m) => m.id == optimisticMessage.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to deliver: $error'),
          backgroundColor: kError,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(kSpaceMd),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusMd)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final isAdmin = user?.role == 'admin';

    return Scaffold(
      backgroundColor: kBackground,
      body: Column(
        children: [
          // ── Channel Selector Bar ──────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
              color: kSurface,
              border: Border(bottom: BorderSide(color: kDivider, width: 1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'COMMUNITY',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                        color: kPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: kPrimary,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: kPrimary.withValues(alpha: 0.6),
                            blurRadius: 6,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    if (isAdmin)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: kPrimary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: kPrimary.withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          'ADMIN MOD',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1,
                            color: kPrimary,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_channels.isEmpty && _loading)
                  const SizedBox(
                    height: 38,
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: kPrimary),
                      ),
                    ),
                  )
                else
                  SizedBox(
                    height: 38,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _channels.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final channel = _channels[index];
                        final isSelected = _selected?.id == channel.id;

                        return GestureDetector(
                          onTap: () => _selectChannel(channel),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: isSelected ? kPrimary : kCard,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isSelected ? kPrimary : kBorder,
                                width: 1.2,
                              ),
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: kPrimary.withValues(alpha: 0.35),
                                        blurRadius: 12,
                                        offset: const Offset(0, 3),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '#',
                                  style: TextStyle(
                                    color: isSelected ? Colors.black : kPrimary,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  channel.name,
                                  style: TextStyle(
                                    color: isSelected ? Colors.black : kTextPrimary,
                                    fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),

          // ── Messages Feed ─────────────────────────────────────────────────
          Expanded(
            child: _loading && _messages.isEmpty
                ? const Center(
                    child: CircularProgressIndicator(color: kPrimary, strokeWidth: 2),
                  )
                : _error != null && _messages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.wifi_off_rounded, size: 48, color: kTextSecondary),
                            const SizedBox(height: 12),
                            Text(
                              _error!,
                              style: TextStyle(color: kTextSecondary, fontSize: 13),
                            ),
                            const SizedBox(height: 16),
                            FilledButton(
                              onPressed: _loadChannels,
                              style: FilledButton.styleFrom(backgroundColor: kPrimary),
                              child: const Text('Retry Connection', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w800)),
                            ),
                          ],
                        ),
                      )
                    : _messages.isEmpty
                        ? _buildEmptyState()
                        : ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            itemCount: _messages.length,
                            itemBuilder: (context, index) {
                              final message = _messages[index];
                              final isOwn = message.authorId == user?.id;
                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 14),
                                child: MessageBubble(
                                  message: message,
                                  isOwn: isOwn,
                                ),
                              );
                            },
                          ),
          ),

          // ── Bottom Composer ───────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            decoration: BoxDecoration(
              color: kSurface,
              border: Border(top: BorderSide(color: kDivider, width: 1)),
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: kCard,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: kBorder, width: 1),
                      ),
                      child: TextField(
                        controller: _controller,
                        style: TextStyle(color: kTextPrimary, fontSize: 15, fontWeight: FontWeight.w500),
                        decoration: InputDecoration(
                          hintText: _selected != null ? 'Message #${_selected!.name}...' : 'Write message...',
                          hintStyle: TextStyle(color: kTextSecondary, fontSize: 14),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        ),
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  BounceTap(
                    onTap: _sendMessage,
                    child: Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [kOrange400, kOrange600],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [flameShadow(1.2)],
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.arrow_upward_rounded,
                          color: Colors.black,
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: kPrimary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(color: kPrimary.withValues(alpha: 0.3)),
              ),
              child: const Center(
                child: Icon(Icons.forum_outlined, size: 34, color: kPrimary),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'CHANNEL SILENT',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
                color: kTextPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Be the spark. Kick off the studio discussion.',
              textAlign: TextAlign.center,
              style: TextStyle(color: kTextSecondary, fontSize: 13),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _QuickStarter(
                  label: '👋 Say hi to classmates',
                  onTap: () => _sendMessage('Hey everyone! Excited for this module.'),
                ),
                _QuickStarter(
                  label: '📚 Discuss assignment',
                  onTap: () => _sendMessage('Has anyone started on the usability study report?'),
                ),
                _QuickStarter(
                  label: '❓ Ask a question',
                  onTap: () => _sendMessage('Quick question regarding the deadline for next week:'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickStarter extends StatelessWidget {
  const _QuickStarter({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      onPressed: onTap,
      label: Text(label),
      backgroundColor: kCard,
      side: BorderSide(color: kBorder),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: kTextPrimary,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    );
  }
}
