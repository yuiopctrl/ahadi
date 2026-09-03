import 'package:flutter/material.dart';

class PlanEditorResult {
  const PlanEditorResult(this.input);
  final Map<String, dynamic> input;
}

Future<PlanEditorResult?> showPlanEditorDialog(
  BuildContext context, {
  Map<String, dynamic>? existing,
}) {
  final isCreate = existing == null;
  final codeController = TextEditingController(
    text: existing?['code'] as String? ?? '',
  );
  final nameController = TextEditingController(
    text: existing?['name'] as String? ?? '',
  );
  final descriptionController = TextEditingController(
    text: existing?['description'] as String? ?? '',
  );
  final currencyController = TextEditingController(
    text: existing?['currency'] as String? ?? 'TZS',
  );
  final priceController = TextEditingController(
    text: '${existing?['price_amount'] ?? 0}',
  );
  final trialDaysController = TextEditingController(
    text: '${existing?['trial_days'] ?? 0}',
  );
  final maxEventsController = TextEditingController(
    text: '${existing?['max_active_events'] ?? 1}',
  );
  final maxMembersController = TextEditingController(
    text: '${existing?['max_members'] ?? 100}',
  );
  final maxUsersController = TextEditingController(
    text: '${existing?['max_users'] ?? 3}',
  );
  final includedSmsController = TextEditingController(
    text: '${existing?['included_sms'] ?? 0}',
  );
  final displayOrderController = TextEditingController(
    text: '${existing?['display_order'] ?? 0}',
  );
  var billingInterval = existing?['billing_interval'] as String? ?? 'MONTHLY';
  var isPublic = existing?['is_public'] as bool? ?? true;
  var isActive = existing?['is_active'] as bool? ?? true;

  return showDialog<PlanEditorResult>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(isCreate ? 'New plan' : 'Edit plan'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isCreate)
                  TextField(
                    controller: codeController,
                    decoration: const InputDecoration(
                      labelText: 'Code (e.g. STANDARD_MONTHLY)',
                    ),
                  ),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(labelText: 'Description'),
                  maxLines: 2,
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: currencyController,
                        decoration: const InputDecoration(
                          labelText: 'Currency',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: priceController,
                        decoration: const InputDecoration(labelText: 'Price'),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                DropdownButtonFormField<String>(
                  initialValue: billingInterval,
                  decoration: const InputDecoration(
                    labelText: 'Billing interval',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'MONTHLY', child: Text('Monthly')),
                    DropdownMenuItem(
                      value: 'QUARTERLY',
                      child: Text('Quarterly'),
                    ),
                    DropdownMenuItem(value: 'YEARLY', child: Text('Yearly')),
                    DropdownMenuItem(value: 'CUSTOM', child: Text('Custom')),
                  ],
                  onChanged: (value) => setState(
                    () => billingInterval = value ?? billingInterval,
                  ),
                ),
                TextField(
                  controller: trialDaysController,
                  decoration: const InputDecoration(labelText: 'Trial days'),
                  keyboardType: TextInputType.number,
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: maxEventsController,
                        decoration: const InputDecoration(
                          labelText: 'Max events',
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: maxMembersController,
                        decoration: const InputDecoration(
                          labelText: 'Max members',
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: maxUsersController,
                        decoration: const InputDecoration(
                          labelText: 'Max users',
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: includedSmsController,
                        decoration: const InputDecoration(
                          labelText: 'Included SMS',
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                TextField(
                  controller: displayOrderController,
                  decoration: const InputDecoration(labelText: 'Display order'),
                  keyboardType: TextInputType.number,
                ),
                SwitchListTile(
                  value: isPublic,
                  title: const Text('Public'),
                  onChanged: (v) => setState(() => isPublic = v),
                ),
                SwitchListTile(
                  value: isActive,
                  title: const Text('Active'),
                  onChanged: (v) => setState(() => isActive = v),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final input = <String, dynamic>{
                if (isCreate) 'code': codeController.text.trim(),
                'name': nameController.text.trim(),
                'description': descriptionController.text.trim(),
                'currency': currencyController.text.trim(),
                'priceAmount':
                    double.tryParse(priceController.text.trim()) ?? 0,
                'billingInterval': billingInterval,
                'trialDays': int.tryParse(trialDaysController.text.trim()) ?? 0,
                'maxActiveEvents':
                    int.tryParse(maxEventsController.text.trim()) ?? 0,
                'maxMembers':
                    int.tryParse(maxMembersController.text.trim()) ?? 0,
                'maxUsers': int.tryParse(maxUsersController.text.trim()) ?? 0,
                'includedSms':
                    int.tryParse(includedSmsController.text.trim()) ?? 0,
                'isPublic': isPublic,
                'isActive': isActive,
                'displayOrder':
                    int.tryParse(displayOrderController.text.trim()) ?? 0,
              };
              Navigator.of(context).pop(PlanEditorResult(input));
            },
            child: Text(isCreate ? 'Create' : 'Save'),
          ),
        ],
      ),
    ),
  );
}
