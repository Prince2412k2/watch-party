import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sc;

import '../../models/models.dart';
import '../../state/chat_provider.dart';
import '../tokens.dart';
import 'empty_state.dart';

/// Party chat, docked beside the player (PLAN §3.8 / E7 / mounted by E5's
/// party screen). Message list with own-message alignment + an input row
/// with a rate-limit hint, matching the web app's chat behavior
/// (`chat:message`, 5 messages / 3s server-side).
class ChatPanel extends ConsumerStatefulWidget {
  const ChatPanel({super.key});

  @override
  ConsumerState<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends ConsumerState<ChatPanel> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  String? _hint;
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() {
      _sending = true;
      _hint = null;
    });
    final error = await ref.read(chatProvider.notifier).send(text);
    if (!mounted) return;
    setState(() {
      _sending = false;
      _hint = error;
    });
    if (error == null) {
      _controller.clear();
      _scrollToEnd();
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(chatProvider);
    final myUserId = ref.watch(currentUserIdProvider);

    ref.listen(chatProvider, (prev, next) {
      if (next.length > (prev?.length ?? 0)) _scrollToEnd();
    });

    return Column(
      children: [
        Expanded(
          child: messages.isEmpty
              ? const EmptyState(
                  title: 'No messages yet',
                  message: 'Say something to the room.',
                  icon: Icons.chat_bubble_outline,
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final m = messages[index];
                    return _ChatBubble(
                      message: m,
                      isOwn: myUserId != null && m.userId == myUserId,
                    );
                  },
                ),
        ),
        _ChatInput(
          controller: _controller,
          hint: _hint,
          busy: _sending,
          onSend: _send,
        ),
      ],
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message, required this.isOwn});

  final ChatMessage message;
  final bool isOwn;

  @override
  Widget build(BuildContext context) {
    final dt = DateTime.fromMillisecondsSinceEpoch(message.timestamp);
    final time =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: isOwn
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isOwn ? 'You' : message.name,
                style: const TextStyle(
                  color: AppColors.dim,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                time,
                style: const TextStyle(color: AppColors.faint, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 2),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: sc.Card(
              filled: true,
              fillColor: isOwn ? AppColors.surface2 : AppColors.surface,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Text(
                message.text,
                style: const TextStyle(
                  color: AppColors.text,
                  fontSize: 13.5,
                  height: 1.35,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatInput extends StatelessWidget {
  const _ChatInput({
    required this.controller,
    required this.hint,
    required this.busy,
    required this.onSend,
  });

  final TextEditingController controller;
  final String? hint;
  final bool busy;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hint != null) ...[
            Text(
              hint!,
              style: const TextStyle(color: AppColors.red, fontSize: 12),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          Row(
            children: [
              Expanded(
                child: sc.TextField(
                  controller: controller,
                  enabled: !busy,
                  onSubmitted: (_) => onSend(),
                  placeholder: const Text('Message the room…'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              sc.IconButton.ghost(
                onPressed: busy ? null : onSend,
                icon: Icon(
                  Icons.send_rounded,
                  color: busy ? AppColors.faint : AppColors.text,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
