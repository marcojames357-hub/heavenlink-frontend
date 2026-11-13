import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:haven_link/core/theme/haven_icons.dart';

import '../../data/review_repository.dart';

typedef UploadPicker = Future<List<UploadFile>> Function({required bool pdf});

const maxUploadBytes = 5 * 1024 * 1024;
const maxUploads = 5;

Future<List<UploadFile>> pickUploads({required bool pdf}) async {
  final picked = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', if (pdf) 'pdf'],
  );
  return [
    for (final file in picked)
      (name: file.name, bytes: await file.readAsBytes()),
  ];
}

/// Lets the guest attach up to five photos (and PDFs for private evidence).
class AttachmentPicker extends StatefulWidget {
  const AttachmentPicker({
    required this.label,
    required this.files,
    this.allowPdf = false,
    this.picker = pickUploads,
    super.key,
  });

  final String label;
  final List<UploadFile> files;
  final bool allowPdf;
  final UploadPicker picker;

  @override
  State<AttachmentPicker> createState() => _AttachmentPickerState();
}

class _AttachmentPickerState extends State<AttachmentPicker> {
  String? _error;

  Future<void> _add() async {
    try {
      final picked = await widget.picker(pdf: widget.allowPdf);
      if (!mounted) return;
      String? error;
      setState(() {
        for (final file in picked) {
          if (widget.files.length >= maxUploads) {
            error = 'You can attach up to $maxUploads files.';
            break;
          }
          if (file.bytes.length > maxUploadBytes) {
            error = '${file.name} is larger than 5 MB.';
            continue;
          }
          widget.files.add(file);
        }
        _error = error;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Files could not be selected.');
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      OutlinedButton.icon(
        onPressed: widget.files.length >= maxUploads ? null : _add,
        icon: const Icon(HavenIcons.addPhotoAlternateOutlined),
        label: Text(widget.label),
      ),
      if (widget.files.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final file in List.of(widget.files))
                InputChip(
                  label: Text(file.name, overflow: TextOverflow.ellipsis),
                  onDeleted: () => setState(() => widget.files.remove(file)),
                ),
            ],
          ),
        ),
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          _error ??
              'JPG, PNG or WebP${widget.allowPdf ? ' or PDF' : ''}, up to 5 MB each.',
          style: TextStyle(
            fontSize: 12,
            color: _error == null
                ? Theme.of(context).hintColor
                : Theme.of(context).colorScheme.error,
          ),
        ),
      ),
    ],
  );
}
