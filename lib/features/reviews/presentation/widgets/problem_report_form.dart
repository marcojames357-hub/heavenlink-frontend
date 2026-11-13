import 'package:flutter/material.dart';
import 'package:haven_link/core/theme/haven_icons.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/review_repository.dart';
import '../../domain/review_models.dart';
import 'attachment_picker.dart';

/// Holds the private problem report being drafted.
class ProblemReportDraft {
  String? category;
  String severity = 'general';
  final description = TextEditingController();
  final List<UploadFile> evidence = [];

  bool get isBlank =>
      category == null && description.text.trim().isEmpty && evidence.isEmpty;

  String? validate() {
    if (category == null) return 'Choose what the report is about.';
    if (description.text.trim().length < 10) {
      return 'Describe the problem in at least 10 characters.';
    }
    return null;
  }

  void dispose() => description.dispose();
}

const reportPrivacyNotice =
    'Your report is private and will not appear publicly on the property\'s review page. It will be shared with authorized HavenLink administrators and, where appropriate, the responsible Stays Agent.';

class ProblemReportFields extends StatefulWidget {
  const ProblemReportFields({
    required this.draft,
    this.picker = pickUploads,
    this.urgentHint = false,
    super.key,
  });

  final ProblemReportDraft draft;
  final UploadPicker picker;
  final bool urgentHint;

  @override
  State<ProblemReportFields> createState() => _ProblemReportFieldsState();
}

class _ProblemReportFieldsState extends State<ProblemReportFields> {
  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: draft.category,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Problem category'),
          items: [
            for (final entry in problemCategories.entries)
              DropdownMenuItem(
                value: entry.key,
                child: Text(entry.value, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (value) => setState(() => draft.category = value),
        ),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 'general', label: Text('General concern')),
            ButtonSegment(
              value: 'urgent',
              label: Text('Urgent — needs quick attention'),
            ),
          ],
          selected: {draft.severity},
          onSelectionChanged: (value) =>
              setState(() => draft.severity = value.first),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: draft.description,
          minLines: 3,
          maxLines: 6,
          maxLength: 3000,
          decoration: const InputDecoration(
            labelText: 'Describe what happened',
            helperText:
                'Describe what happened, when it happened, and what assistance you need.',
            helperMaxLines: 2,
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 8),
        AttachmentPicker(
          label: 'Add supporting photos or documents',
          files: draft.evidence,
          allowPdf: true,
          picker: widget.picker,
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: HavenTheme.veryLightMint,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(HavenIcons.lockOutline, size: 18, color: HavenTheme.forest),
              SizedBox(width: 8),
              Expanded(child: Text(reportPrivacyNotice)),
            ],
          ),
        ),
      ],
    );
  }
}
