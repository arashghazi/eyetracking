import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

/// Lists what every exported column and summary field means.
class DataDictionaryDialog extends StatelessWidget {
  const DataDictionaryDialog({super.key, required this.entries});

  final List<DictionaryEntry> entries;

  static Future<void> show(BuildContext context, List<DictionaryEntry> entries) =>
      showDialog<void>(
        context: context,
        builder: (_) => DataDictionaryDialog(entries: entries),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Data dictionary'),
      content: SizedBox(
        width: 720,
        child: entries.isEmpty
            ? const Text('The server sent an empty dictionary.')
            : Container(
                key: const Key('dictionary-table'),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(kRadius),
                ),
                child: SingleChildScrollView(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 680),
                      child: DataTable(
                        columnSpacing: 20,
                        dataRowMinHeight: 36,
                        dataRowMaxHeight: 72,
                        headingRowHeight: 38,
                        columns: const [
                          DataColumn(label: Text('Name')),
                          DataColumn(label: Text('Type')),
                          DataColumn(label: Text('Unit')),
                          DataColumn(label: Text('Meaning')),
                        ],
                        rows: [
                          for (final e in entries)
                            DataRow(cells: [
                              DataCell(Text(
                                e.name,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontFamilyFallback: kMonospaceFallback,
                                  fontWeight: FontWeight.w600,
                                ),
                              )),
                              DataCell(Text(e.type.isEmpty ? '—' : e.type)),
                              DataCell(Text(e.unit.isEmpty ? '—' : e.unit)),
                              DataCell(ConstrainedBox(
                                constraints: const BoxConstraints(
                                  minWidth: 200,
                                  maxWidth: 360,
                                ),
                                child: Text(
                                  e.meaning,
                                  style: theme.textTheme.bodyMedium,
                                ),
                              )),
                            ]),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
      ),
      actions: [
        TextButton(
          key: const Key('close-dictionary'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
