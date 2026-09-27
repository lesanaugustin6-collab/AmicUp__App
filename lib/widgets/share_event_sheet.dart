import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/message_forwarding.dart';
import '../theme/app_theme.dart';

Future<void> showShareEventSheet(
  BuildContext context, {
  required String eventId,
  required String title,
  required DateTime startsAt,
  required String location,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ShareEventSheet(
      eventId: eventId,
      title: title,
      startsAt: startsAt,
      location: location,
    ),
  );
}

class _ShareEventSheet extends StatefulWidget {
  const _ShareEventSheet({required this.eventId, required this.title, required this.startsAt, required this.location});
  final String eventId;
  final String title;
  final DateTime startsAt;
  final String location;
  @override
  State<_ShareEventSheet> createState() => _ShareEventSheetState();
}

class _ShareEventSheetState extends State<_ShareEventSheet> {
  final _service = MessageForwarding(Supabase.instance.client);
  late final Future<List<ForwardDestination>> _destinations = _service.destinations();
  ForwardDestination? _selected;
  bool _sending = false;

  Future<void> _send() async {
    if (_selected == null || _sending) return;
    setState(() => _sending = true);
    try {
      await _service.send({
        'content': '[EVENT]:${widget.eventId}|${widget.title}|${widget.startsAt.toUtc().toIso8601String()}|${widget.location}',
      }, _selected!);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Event shared')));
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not share event: $error')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .62,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Share event', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppTheme.of(context).muted)),
          const SizedBox(height: 12),
          Expanded(child: FutureBuilder<List<ForwardDestination>>(
            future: _destinations,
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              final groups = snapshot.data!.where((d) => d.group).toList();
              final directs = snapshot.data!.where((d) => !d.group).toList();
              Widget tile(ForwardDestination item) => ListTile(
                leading: Icon(item.group ? Icons.groups_rounded : Icons.person_outline_rounded),
                title: Text(item.name),
                subtitle: Text(item.group ? 'Group chat' : 'Direct message'),
                trailing: Icon(
                  _selected?.id == item.id && _selected?.group == item.group
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: _selected?.id == item.id && _selected?.group == item.group
                      ? AppTheme.of(context).violetStrong
                      : AppTheme.of(context).muted,
                ),
                onTap: _sending ? null : () => setState(() => _selected = item),
              );
              return ListView(children: [
                if (groups.isNotEmpty) ...[const _SectionTitle('GROUP CHATS'), ...groups.map(tile)],
                if (directs.isNotEmpty) ...[const _SectionTitle('DIRECT MESSAGES'), ...directs.map(tile)],
                if (groups.isEmpty && directs.isEmpty) const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No conversations available'))),
              ]);
            },
          )),
          SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _selected == null || _sending ? null : _send, icon: const Icon(Icons.send_rounded), label: Text(_sending ? 'Sharing…' : 'Share'))),
        ]),
      ),
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
    child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: .8, color: AppTheme.of(context).muted)),
  );
}
