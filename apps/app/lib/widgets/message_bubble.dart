import 'package:edtech_app/models/chat_message.dart';
import 'package:edtech_app/theme.dart';
import 'package:flutter/material.dart';

class MessageBubble extends StatefulWidget {
  final ChatMessage message;
  final bool isOwn;

  const MessageBubble({super.key, required this.message, required this.isOwn});

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );

  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
  );

  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.3),
    end: Offset.zero,
  ).animate(CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutBack,
  ));

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _formatTime(DateTime date) {
    return '${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Align(
          alignment:
              widget.isOwn ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.72,
            ),
            margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              gradient: widget.isOwn
                  ? const LinearGradient(
                      colors: [kOrange500, kOrange700],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              color: widget.isOwn
                  ? null
                  : (isDark
                      ? const Color(0xFF1A1A1A)
                      : const Color(0xFFF0F0F0)),
              border: widget.isOwn
                  ? null
                  : Border.all(
                      color: const Color(0xFF282828),
                      width: 0.5,
                    ),
              borderRadius: widget.isOwn
                  ? BorderRadius.circular(18)
                      .copyWith(bottomRight: const Radius.circular(4))
                  : BorderRadius.circular(18)
                      .copyWith(bottomLeft: const Radius.circular(4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.message.body,
                  style: TextStyle(
                    color: widget.isOwn
                        ? Colors.white
                        : (isDark
                            ? const Color(0xFFF7F7F7)
                            : const Color(0xFF0A0A0A)),
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatTime(widget.message.sentAt),
                  style: TextStyle(
                    color: widget.isOwn
                        ? Colors.white60
                        : const Color(0xFF9A9A9A),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
