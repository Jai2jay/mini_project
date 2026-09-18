import 'package:flutter/material.dart';
import 'temporary_contact_service.dart';

/// Screen displaying all active temporary contacts currently stored in the app,
/// their live ticking countdowns, and scheduled deletion times.
class TemporaryContactsScreen extends StatelessWidget {
  const TemporaryContactsScreen({super.key});

  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    final isToday =
        dt.year == now.year && dt.month == now.month && dt.day == now.day;
    final isTomorrow =
        dt.year == now.year && dt.month == now.month && dt.day == now.day + 1;
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    final timeStr = '$hour:$minute';

    final monthNames = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];

    if (isToday) {
      return 'Today at $timeStr';
    } else if (isTomorrow) {
      return 'Tomorrow at $timeStr';
    } else {
      return '${dt.day} ${monthNames[dt.month]} ${dt.year}, $timeStr';
    }
  }

  String _formatRemaining(Duration diff) {
    if (diff.isNegative) {
      return 'Expiring now...';
    }
    if (diff.inSeconds < 60) {
      return '${diff.inSeconds}s remaining';
    }
    if (diff.inMinutes < 60) {
      final s = diff.inSeconds % 60;
      return '${diff.inMinutes}m ${s}s remaining';
    }
    if (diff.inHours < 24) {
      final m = diff.inMinutes % 60;
      return '${diff.inHours}h ${m}m remaining';
    }
    final h = diff.inHours % 24;
    return '${diff.inDays}d ${h}h remaining';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E1118),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E1118),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Temporary Contacts',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          ValueListenableBuilder<List<ScheduledContact>>(
            valueListenable: TemporaryContactService().activeContacts,
            builder: (context, contacts, _) {
              if (contacts.isEmpty) return const SizedBox.shrink();
              return TextButton(
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: const Color(0xFF161922),
                      title: const Text('Clear All Timers?',
                          style: TextStyle(color: Colors.white)),
                      content: const Text(
                        'This will stop all auto-delete timers for temporary contacts. '
                        'Contacts already in your phonebook will remain permanent.',
                        style: TextStyle(color: Colors.white70),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(false),
                          child: const Text('Cancel'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.of(ctx).pop(true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                          ),
                          child: const Text('Clear All'),
                        ),
                      ],
                    ),
                  );

                  if (confirm == true) {
                    await TemporaryContactService().clearAll();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Cleared all temporary contact timers.'),
                        ),
                      );
                    }
                  }
                },
                child: const Text(
                  'Clear All',
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: ValueListenableBuilder<List<ScheduledContact>>(
          valueListenable: TemporaryContactService().activeContacts,
          builder: (context, contacts, _) {
            if (contacts.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: const Color(0xFF161922),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFF242838),
                            width: 1.5,
                          ),
                        ),
                        child: const Icon(
                          Icons.timer_outlined,
                          size: 54,
                          color: Color(0xFF6C93D6),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'No Active Temporary Contacts',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'When you scan and save contacts with temporary expiry enabled, '
                        'their auto-delete timers and countdowns will appear here.',
                        style: TextStyle(
                          color: Color(0xFF8F97A6),
                          fontSize: 13,
                          height: 1.4,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            }

            return ListView(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              children: [
                // Info header card
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1B2335),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF2A3752)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: Color(0xFF6C93D6),
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${contacts.length} active contact${contacts.length == 1 ? '' : 's'} scheduled to auto-delete when timer reaches zero.',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Contacts list
                ...contacts.map((contact) {
                  final diff = contact.remaining;
                  final isUrgent = diff.inSeconds <= 60;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF141720),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isUrgent
                            ? Colors.redAccent.withValues(alpha: 0.6)
                            : const Color(0xFF232838),
                        width: 1.2,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1B2335),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.person,
                                color: Color(0xFF6C93D6),
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    contact.name,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.phone,
                                        size: 13,
                                        color: Color(0xFF8F97A6),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        contact.phone,
                                        style: const TextStyle(
                                          color: Color(0xFF8F97A6),
                                          fontSize: 13,
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.delete_outline,
                                color: Colors.redAccent,
                                size: 20,
                              ),
                              tooltip: 'Delete contact now',
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    backgroundColor: const Color(0xFF161922),
                                    title: const Text('Delete Contact?',
                                        style: TextStyle(color: Colors.white)),
                                    content: Text(
                                      'Delete \'${contact.name}\' from phonebook now?',
                                      style: const TextStyle(color: Colors.white70),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.of(ctx).pop(false),
                                        child: const Text('Cancel'),
                                      ),
                                      ElevatedButton(
                                        onPressed: () =>
                                            Navigator.of(ctx).pop(true),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.redAccent,
                                        ),
                                        child: const Text('Delete'),
                                      ),
                                    ],
                                  ),
                                );

                                if (confirm == true) {
                                  await TemporaryContactService()
                                      .removeContact(contact, deleteFromPhone: true);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          '\'${contact.name}\' deleted from phonebook.',
                                        ),
                                      ),
                                    );
                                  }
                                }
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Divider(color: Color(0xFF232838), height: 1),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Icon(
                              Icons.alarm,
                              color: Color(0xFF8F97A6),
                              size: 14,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Expires: ${_formatDateTime(contact.expiryDateTime)}',
                              style: const TextStyle(
                                color: Color(0xFF8F97A6),
                                fontSize: 12,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: isUrgent
                                    ? Colors.redAccent.withValues(alpha: 0.2)
                                    : const Color(0xFF2B3A5E),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: isUrgent
                                      ? Colors.redAccent
                                      : const Color(0xFF3E5488),
                                  width: 0.8,
                                ),
                              ),
                              child: Text(
                                _formatRemaining(diff),
                                style: TextStyle(
                                  color: isUrgent
                                      ? Colors.redAccent
                                      : const Color(0xFF8FB7FF),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }),
              ],
            );
          },
        ),
      ),
    );
  }
}
