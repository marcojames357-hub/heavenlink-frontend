import 'package:flutter/material.dart';
import 'package:haven_link/core/theme/haven_icons.dart';

import '../../../core/theme/app_theme.dart';
import '../data/review_repository.dart';
import '../domain/review_models.dart';
import 'widgets/attachment_picker.dart';
import 'widgets/guest_review_card.dart';
import 'widgets/problem_report_form.dart';
import 'widgets/star_rating.dart';

const _categoryOrder = ['overall', ...reviewRatingFields];

/// Guest flow: rate nine categories, share a public review, optionally
/// file a private problem report, then see a confirmation.
class ReviewFlowScreen extends StatefulWidget {
  const ReviewFlowScreen({
    required this.repository,
    required this.trip,
    this.reportOnly = false,
    this.picker = pickUploads,
    super.key,
  });

  final ReviewRepository repository;
  final TripBooking trip;
  final bool reportOnly;
  final UploadPicker picker;

  @override
  State<ReviewFlowScreen> createState() => _ReviewFlowScreenState();
}

class _ReviewFlowScreenState extends State<ReviewFlowScreen> {
  final _ratings = {for (final key in _categoryOrder) key: 0};
  final _comment = TextEditingController();
  final _photos = <UploadFile>[];
  final _draft = ProblemReportDraft();
  var _step = 0;
  var _reporting = false;
  var _saving = false;
  String? _error;
  GuestReview? _submittedReview;
  ProblemReportItem? _submittedReport;
  String? _reportError;

  @override
  void initState() {
    super.initState();
    _reporting = widget.reportOnly;
  }

  @override
  void dispose() {
    _comment.dispose();
    _draft.dispose();
    super.dispose();
  }

  bool get _allRated => _ratings.values.every((value) => value > 0);

  void _next() {
    if (!_allRated) {
      setState(() => _error = 'Please rate all nine categories to continue.');
      return;
    }
    setState(() {
      _error = null;
      _step = 1;
    });
  }

  Future<void> _submit() async {
    final trip = widget.trip;
    final commentText = _comment.text.trim();
    if (!widget.reportOnly) {
      if (commentText.isNotEmpty && commentText.length < 10) {
        setState(
          () => _error = 'Your written review must be at least 10 characters.',
        );
        return;
      }
    }
    final sendReport = _reporting && !_draft.isBlank;
    if (_reporting) {
      final problem = _draft.validate();
      if (problem != null && (widget.reportOnly || !_draft.isBlank)) {
        setState(() => _error = problem);
        return;
      }
    }
    final sendReview = !widget.reportOnly && _allRated;
    if (!sendReview && !sendReport) {
      setState(() => _error = 'Nothing to submit yet.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _reportError = null;
    });
    // Review and report are independent: one failing never discards the other.
    if (sendReview && _submittedReview == null) {
      try {
        _submittedReview = await widget.repository.submitReview(
          bookingId: trip.id,
          overallRating: _ratings['overall']!,
          ratings: {
            for (final field in reviewRatingFields) field: _ratings[field]!,
          },
          comment: commentText.isEmpty ? null : commentText,
          photos: List.of(_photos),
        );
      } catch (error) {
        if (mounted) {
          setState(() {
            _saving = false;
            _error = error.toString().replaceFirst('Bad state: ', '');
          });
        }
        return;
      }
    }
    if (sendReport && _submittedReport == null) {
      try {
        _submittedReport = await widget.repository.submitProblemReport(
          bookingId: trip.id,
          category: _draft.category!,
          severity: _draft.severity,
          description: _draft.description.text.trim(),
          evidence: List.of(_draft.evidence),
        );
      } catch (error) {
        _reportError = error.toString().replaceFirst('Bad state: ', '');
      }
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (_reportError != null && _submittedReview == null) {
        _error = _reportError;
      } else {
        _step = 2;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.reportOnly ? 'Report a Problem' : 'Review Your Stay';
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(HavenIcons.homeWorkOutlined, size: 22),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'HavenLink · $title',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_step < 2) _TripHeader(trip: widget.trip),
                if (_step < 2) const SizedBox(height: 12),
                if (_step == 0 && !widget.reportOnly) ..._rateStep(),
                if ((_step == 1 || widget.reportOnly) && _step < 2)
                  ..._shareStep(),
                if (_step == 2) ..._confirmation(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _rateStep() => [
    Text('Rate Your Stay', style: Theme.of(context).textTheme.titleLarge),
    const SizedBox(height: 4),
    for (final key in _categoryOrder)
      StarRatingInput(
        label: reviewCategoryLabels[key]!,
        question: reviewCategoryQuestions[key]!,
        value: _ratings[key]!,
        onChanged: (value) => setState(() {
          _ratings[key] = value;
          _error = null;
        }),
      ),
    if (_error != null) _ErrorText(_error!),
    const SizedBox(height: 8),
    Align(
      alignment: Alignment.centerRight,
      child: FilledButton(onPressed: _next, child: const Text('Continue')),
    ),
  ];

  List<Widget> _shareStep() => [
    if (!widget.reportOnly) ...[
      Text(
        'Share Your Experience',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 4),
      const Text(
        'Tell future guests what you liked about your stay and what could be improved.',
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _comment,
        minLines: 4,
        maxLines: 8,
        maxLength: 3000,
        decoration: const InputDecoration(
          labelText: 'Your public review',
          hintText:
              'The apartment was clean and comfortable. The location was convenient, and the host responded quickly whenever we needed assistance.',
          alignLabelWithHint: true,
        ),
      ),
      const SizedBox(height: 8),
      AttachmentPicker(
        label: 'Add photos (optional)',
        files: _photos,
        picker: widget.picker,
      ),
      const Divider(height: 36),
    ],
    Row(
      children: [
        const Icon(HavenIcons.reportProblemOutlined, color: HavenTheme.forest),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'REPORT A PROBLEM OR CONCERN',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      ],
    ),
    const SizedBox(height: 6),
    const Text(
      'Did you experience any problems, unexpected situations, or uncertainties during your stay? Tell us so HavenLink and the responsible Stays Agent can investigate and assist.',
    ),
    if (!widget.reportOnly)
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('I want to report a problem or concern'),
        subtitle: const Text('Optional and separate from your public review.'),
        value: _reporting,
        onChanged: (value) => setState(() => _reporting = value),
      ),
    if (_reporting) ...[
      const SizedBox(height: 8),
      ProblemReportFields(draft: _draft, picker: widget.picker),
    ],
    if (_error != null) _ErrorText(_error!),
    const SizedBox(height: 16),
    Wrap(
      alignment: WrapAlignment.spaceBetween,
      runSpacing: 8,
      spacing: 8,
      children: [
        if (!widget.reportOnly)
          TextButton.icon(
            onPressed: _saving ? null : () => setState(() => _step = 0),
            icon: const Icon(HavenIcons.arrowBack),
            label: const Text('Back to ratings'),
          ),
        FilledButton.icon(
          onPressed: _saving ? null : _submit,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(HavenIcons.sendOutlined),
          label: Text(widget.reportOnly ? 'Submit report' : 'Submit review'),
        ),
      ],
    ),
  ];

  List<Widget> _confirmation(BuildContext context) {
    final review = _submittedReview;
    final report = _submittedReport;
    return [
      const SizedBox(height: 16),
      const Icon(HavenIcons.checkCircle, size: 64, color: HavenTheme.forest),
      const SizedBox(height: 12),
      Text(
        review != null
            ? 'Thank you for reviewing your stay!'
            : 'Your report has been received',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 8),
      if (review != null)
        const Text(
          'Your review has been received and will appear on the property page according to HavenLink\'s publication and moderation policy.',
          textAlign: TextAlign.center,
        ),
      if (report != null) ...[
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                const Text(
                  'Your concern has been received. You can track its progress in your account.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                SelectableText(
                  'Reference ${report.reference}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ),
      ],
      if (_reportError != null) ...[
        const SizedBox(height: 12),
        _ErrorText(
          'Your review was saved, but the problem report could not be sent: $_reportError. You can report it again from My Trips.',
        ),
      ],
      const SizedBox(height: 20),
      Wrap(
        alignment: WrapAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          if (review != null)
            OutlinedButton.icon(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => Dialog(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(8),
                      child: GuestReviewCard(review: review),
                    ),
                  ),
                ),
              ),
              icon: const Icon(HavenIcons.rateReviewOutlined),
              label: const Text('View My Review'),
            ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Back to My Trips'),
          ),
        ],
      ),
    ];
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text(
      message,
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    ),
  );
}

class _TripHeader extends StatelessWidget {
  const _TripHeader({required this.trip});

  final TripBooking trip;

  @override
  Widget build(BuildContext context) {
    final image = trip.imageUrl.isEmpty
        ? const Icon(HavenIcons.hotelOutlined, size: 36)
        : Image.network(
            trip.imageUrl,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                const Icon(HavenIcons.hotelOutlined, size: 36),
          );
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(width: 84, height: 84, child: image),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    trip.propertyName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  if (trip.location.isNotEmpty)
                    Text(
                      trip.location,
                      style: const TextStyle(color: HavenTheme.muted),
                    ),
                  Text(
                    '${formatTripDate(trip.checkIn)} – ${formatTripDate(trip.checkOut)} · ${trip.nights} night${trip.nights == 1 ? '' : 's'}',
                  ),
                  if (trip.phase == 'completed')
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            HavenIcons.verified,
                            size: 16,
                            color: HavenTheme.forest,
                          ),
                          SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              'Verified completed stay',
                              style: TextStyle(
                                color: HavenTheme.forest,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String formatTripDate(DateTime date) {
  const months = [
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
    'Dec',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}
