import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/message_forwarding.dart';

Future<void> showForwardMessageSheet(
  BuildContext context,
  Map<String, dynamic> message,
) async {
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ForwardMessageSheet(message: message),
  );
  if (sent == true && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Message forwarded')));
  }
}

class _ForwardMessageSheet extends StatefulWidget {
  const _ForwardMessageSheet({required this.message});
  final Map<String, dynamic> message;
  @override
  State<_ForwardMessageSheet> createState() => _ForwardMessageSheetState();
}

class _ForwardMessageSheetState extends State<_ForwardMessageSheet> {
  final _service = MessageForwarding(Supabase.instance.client);
  Future<List<ForwardDestination>> _loadDestinations() => _service.destinations(
    excludedSenderId: widget.message['sender_id']?.toString(),
  );
  late Future<List<ForwardDestination>> _destinations = _loadDestinations();
  ForwardDestination? _selected;
  String _query = '';
  bool _sending = false;
  String? _error;
  Future<void> _send() async {
    if (_selected == null || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await _service.send(widget.message, _selected!);
      if (mounted) {
        setState(() => _sending = false);
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is StateError
              ? error.message.toString()
              : error is PostgrestException
              ? 'Could not forward (${error.code}): ${error.message}'
              : 'Delivery could not be confirmed. Check the destination chat before retrying.',
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_sending,
    child: SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .55,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Forward message',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                forwardText(widget.message).isEmpty
                    ? 'Photo message'
                    : forwardText(widget.message),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                enabled: !_sending,
                decoration: const InputDecoration(
                  hintText: 'Search conversations',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) =>
                    setState(() => _query = value.toLowerCase()),
              ),
              Expanded(
                child: FutureBuilder<List<ForwardDestination>>(
                  future: _destinations,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                        child: TextButton(
                          onPressed: () => setState(
                            () => _destinations = _loadDestinations(),
                          ),
                          child: const Text(
                            'Could not load conversations. Retry',
                          ),
                        ),
                      );
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final targets = snapshot.data!
                        .where((d) => d.name.toLowerCase().contains(_query))
                        .toList();
                    if (targets.isEmpty) {
                      return const Center(
                        child: Text('No conversations found'),
                      );
                    }
                    final groups = targets.where((target) => target.group).toList();
                    final directs = targets.where((target) => !target.group).toList();
                    Widget targetTile(ForwardDestination target) {
                        final selected =
                            _selected?.id == target.id &&
                            _selected?.group == target.group;
                        return ListTile(
                          enabled: !_sending,
                          selected: selected,
                          leading: Icon(
                            target.group
                                ? Icons.group_outlined
                                : Icons.person_outline,
                          ),
                          title: Text(
                            target.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            target.group ? 'Group' : 'Direct message',
                          ),
                          trailing: Icon(
                            selected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                          ),
                          onTap: () {
                            FocusScope.of(context).unfocus();
                            setState(() => _selected = target);
                          },
                        );
                    }
                    return ListView(
                      children: [
                        if (groups.isNotEmpty) ...[
                          const Padding(
                            padding: EdgeInsets.fromLTRB(8, 12, 8, 4),
                            child: Text('GROUP CHATS', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                          ),
                          ...groups.map(targetTile),
                        ],
                        if (directs.isNotEmpty) ...[
                          const Padding(
                            padding: EdgeInsets.fromLTRB(8, 12, 8, 4),
                            child: Text('DIRECT MESSAGES', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                          ),
                          ...directs.map(targetTile),
                        ],
                      ],
                    );
                  },
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _selected == null || _sending ? null : _send,
                  child: Text(_sending ? 'Sending…' : 'Forward'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
