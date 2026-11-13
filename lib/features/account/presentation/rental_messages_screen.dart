import 'package:flutter/material.dart';
import 'package:haven_link/core/theme/haven_icons.dart';

import '../../../core/theme/app_theme.dart';
import '../data/customer_data_repository.dart';

class RentalMessagesScreen extends StatefulWidget {
  const RentalMessagesScreen({
    required this.repository,
    required this.currentUserId,
    required this.isAgent,
    this.listingId,
    super.key,
  });

  final CustomerDataRepository repository;
  final String currentUserId;
  final bool isAgent;
  final String? listingId;

  @override
  State<RentalMessagesScreen> createState() => _RentalMessagesScreenState();
}

class _RentalMessagesScreenState extends State<RentalMessagesScreen> {
  late Future<List<Map<String, dynamic>>> _conversations;

  @override
  void initState() {
    super.initState();
    _conversations = _loadConversations();
  }

  Future<List<Map<String, dynamic>>> _loadConversations() async {
    final conversations = await widget.repository.loadRentalConversations();
    return conversations
        .where(
          (conversation) =>
              widget.listingId == null ||
              conversation['listingId'] == widget.listingId,
        )
        .toList(growable: false);
  }

  Future<void> _refresh() async {
    final next = _loadConversations();
    setState(() => _conversations = next);
    try {
      await next;
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.isAgent ? 'Rental Messages' : 'Messages'),
      actions: [
        IconButton(onPressed: _refresh, icon: const Icon(HavenIcons.refresh)),
      ],
    ),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _conversations,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(HavenIcons.cloudOffOutlined, size: 40),
                  const SizedBox(height: 12),
                  Text('Messages could not be loaded: ${snapshot.error}'),
                  TextButton(onPressed: _refresh, child: const Text('Retry')),
                ],
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final conversations = snapshot.data!;
        if (conversations.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    HavenIcons.chatBubbleOutline,
                    color: HavenTheme.muted,
                    size: 44,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.isAgent
                        ? 'No unlocked rental conversations yet'
                        : 'Unlock this property’s contact details to message the agent.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: conversations.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final conversation = conversations[index];
              final property =
                  conversation['property'] as Map<String, dynamic>? ??
                  const <String, dynamic>{};
              final customer =
                  conversation['customer'] as Map<String, dynamic>? ??
                  const <String, dynamic>{};
              final lastMessage =
                  conversation['lastMessage'] as Map<String, dynamic>?;
              final label = widget.isAgent
                  ? customer['fullName'] as String? ?? 'Customer'
                  : property['name'] as String? ?? 'Rental property';
              final detail =
                  lastMessage?['body'] as String? ??
                  (widget.isAgent
                      ? 'Contact unlocked'
                      : 'Message Rental Agent');
              return Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(HavenIcons.homeWorkOutlined),
                  ),
                  title: Text(label),
                  subtitle: Text(
                    '${property['name'] ?? 'Rental property'} · $detail',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: (conversation['unreadCount'] as num? ?? 0) > 0
                      ? CircleAvatar(
                          radius: 12,
                          backgroundColor: HavenTheme.teal,
                          child: Text(
                            '${conversation['unreadCount']}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                            ),
                          ),
                        )
                      : const Icon(HavenIcons.chevronRight),
                  onTap: () async {
                    await Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (context) => _RentalThreadScreen(
                          repository: widget.repository,
                          currentUserId: widget.currentUserId,
                          listingId: conversation['listingId'] as String,
                          customerId: conversation['customerId'] as String,
                          title: label,
                          propertyName:
                              property['name'] as String? ?? 'Rental property',
                        ),
                      ),
                    );
                    if (mounted) _refresh();
                  },
                ),
              );
            },
          ),
        );
      },
    ),
  );
}

class _RentalThreadScreen extends StatefulWidget {
  const _RentalThreadScreen({
    required this.repository,
    required this.currentUserId,
    required this.listingId,
    required this.customerId,
    required this.title,
    required this.propertyName,
  });

  final CustomerDataRepository repository;
  final String currentUserId;
  final String listingId;
  final String customerId;
  final String title;
  final String propertyName;

  @override
  State<_RentalThreadScreen> createState() => _RentalThreadScreenState();
}

class _RentalThreadScreenState extends State<_RentalThreadScreen> {
  final _messageController = TextEditingController();
  late Future<List<Map<String, dynamic>>> _messages;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _messages = _loadMessages();
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _loadMessages() =>
      widget.repository.loadRentalMessages(
        listingId: widget.listingId,
        customerId: widget.customerId,
      );

  Future<void> _send() async {
    final body = _messageController.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.repository.sendRentalMessage(
        listingId: widget.listingId,
        customerId: widget.customerId,
        body: body,
      );
      _messageController.clear();
      setState(() => _messages = _loadMessages());
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: HavenTheme.lightMint,
          child: Text(
            widget.propertyName,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _messages,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Text(
                    'Messages could not be loaded: ${snapshot.error}',
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final messages = snapshot.data!;
              if (messages.isEmpty) {
                return const Center(
                  child: Text('Start the conversation with a message.'),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  final message = messages[index];
                  final mine = message['senderId'] == widget.currentUserId;
                  return Align(
                    alignment: mine
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 520),
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: mine ? HavenTheme.lightMint : Colors.white,
                        border: Border.all(color: HavenTheme.border),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(message['body'] as String? ?? ''),
                    ),
                  );
                },
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 2000,
                    decoration: const InputDecoration(
                      hintText: 'Write a message',
                      counterText: '',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: 'Send message',
                  onPressed: _sending ? null : _send,
                  icon: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(HavenIcons.send),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
