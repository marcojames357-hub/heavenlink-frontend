/// Ratings the guest gives besides the independent Overall Experience rating.
const reviewRatingFields = [
  'cleanliness',
  'accuracy',
  'checkIn',
  'communication',
  'location',
  'value',
  'comfort',
  'amenities',
];

const reviewCategoryLabels = {
  'overall': 'Overall Experience',
  'cleanliness': 'Cleanliness',
  'accuracy': 'Accuracy',
  'checkIn': 'Check-in',
  'communication': 'Communication',
  'location': 'Location',
  'value': 'Value for Money',
  'comfort': 'Comfort',
  'amenities': 'Amenities & Facilities',
};

const reviewCategoryQuestions = {
  'overall': 'How would you rate your overall stay?',
  'cleanliness':
      'How clean were the rooms, bathrooms, bedding, and other facilities?',
  'accuracy':
      'Did the property match its photos, description, and advertised amenities?',
  'checkIn': 'How convenient and organized was the check-in process?',
  'communication':
      'How responsive, helpful, and professional was the Stays Agent or host?',
  'location': 'How convenient was the property\'s location?',
  'value': 'Was the stay worth the amount you paid?',
  'comfort':
      'How comfortable were the beds, furniture, rooms, and overall accommodation?',
  'amenities':
      'How would you rate the condition and functionality of the advertised amenities and facilities?',
};

const ratingWords = ['', 'Poor', 'Fair', 'Average', 'Good', 'Excellent'];

const problemCategories = {
  'maintenance': 'Maintenance or broken facilities',
  'cleanliness': 'Cleanliness or hygiene',
  'utilities': 'Water, electricity, or internet issues',
  'safety': 'Security or safety concerns',
  'charges': 'Unexpected charges or payment issues',
  'misleading_info': 'Misleading property information',
  'staff_behavior': 'Agent or staff behavior',
  'other': 'Uncertainty or other concerns',
};

const reportStatusLabels = {
  'open': 'Open',
  'under_review': 'Under Review',
  'awaiting_agent': 'Awaiting Agent Response',
  'awaiting_customer': 'Awaiting Customer Response',
  'resolved': 'Resolved',
  'closed': 'Closed',
};

class TripBooking {
  const TripBooking({
    required this.id,
    required this.reference,
    required this.propertyId,
    required this.propertyName,
    required this.imageUrl,
    required this.location,
    required this.checkIn,
    required this.checkOut,
    required this.nights,
    required this.status,
    required this.phase,
    required this.totalTzs,
    required this.paymentStatus,
    required this.canReview,
    required this.reportCount,
    this.reviewBlockedReason,
    this.reviewDeadline,
    this.review,
  });

  final String id;
  final String reference;
  final String propertyId;
  final String propertyName;
  final String imageUrl;
  final String location;
  final DateTime checkIn;
  final DateTime checkOut;
  final int nights;
  final String status;
  final String phase;
  final int totalTzs;
  final String paymentStatus;
  final bool canReview;
  final int reportCount;
  final String? reviewBlockedReason;
  final DateTime? reviewDeadline;
  final GuestReview? review;

  bool get hasReview => review != null;

  factory TripBooking.fromJson(Map<String, dynamic> json) {
    final property = json['property'] as Map<String, dynamic>? ?? const {};
    final review = json['review'] as Map<String, dynamic>?;
    return TripBooking(
      id: json['id'] as String? ?? '',
      reference: json['reference'] as String? ?? json['id'] as String? ?? '',
      propertyId: property['id'] as String? ?? '',
      propertyName: property['name'] as String? ?? 'Stay',
      imageUrl: property['imageUrl'] as String? ?? '',
      location: [
        property['neighborhood'],
        property['city'],
      ].whereType<String>().where((part) => part.isNotEmpty).join(', '),
      checkIn:
          DateTime.tryParse(json['checkIn'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
      checkOut:
          DateTime.tryParse(json['checkOut'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
      nights: (json['nights'] as num?)?.toInt() ?? 1,
      status: json['status'] as String? ?? '',
      phase: json['phase'] as String? ?? 'upcoming',
      totalTzs: (json['totalTzs'] as num?)?.toInt() ?? 0,
      paymentStatus: json['paymentStatus'] as String? ?? 'not_recorded',
      canReview: json['canReview'] as bool? ?? false,
      reportCount: (json['reportCount'] as num?)?.toInt() ?? 0,
      reviewBlockedReason: json['reviewBlockedReason'] as String?,
      reviewDeadline: DateTime.tryParse(
        json['reviewDeadline'] as String? ?? '',
      )?.toLocal(),
      review: review == null ? null : GuestReview.fromJson(review),
    );
  }
}

class GuestReview {
  const GuestReview({
    required this.id,
    required this.displayName,
    required this.createdAt,
    required this.overallRating,
    required this.criteria,
    required this.title,
    required this.comment,
    this.stayDate,
    this.images = const [],
    this.agentResponse,
    this.agentResponseAt,
    this.status = 'published',
    this.propertyId,
    this.propertyName,
  });

  final String id;
  final String displayName;
  final DateTime createdAt;
  final DateTime? stayDate;
  final double overallRating;
  final Map<String, int> criteria;
  final String? title;
  final String? comment;
  final List<String> images;
  final String? agentResponse;
  final DateTime? agentResponseAt;
  final String status;
  final String? propertyId;
  final String? propertyName;

  factory GuestReview.fromJson(Map<String, dynamic> json) {
    final reviewer = json['reviewer'] as Map<String, dynamic>? ?? const {};
    return GuestReview(
      id: json['id'] as String? ?? '',
      displayName: reviewer['displayName'] as String? ?? 'Haven Link guest',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
      stayDate: DateTime.tryParse(json['stayDate'] as String? ?? '')?.toLocal(),
      overallRating: (json['overallRating'] as num?)?.toDouble() ?? 0,
      criteria: {
        for (final field in reviewRatingFields)
          field: (json[field] as num?)?.toInt() ?? 0,
      },
      title: json['title'] as String?,
      comment: json['comment'] as String?,
      images: (json['images'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      agentResponse: json['agentResponse'] as String?,
      agentResponseAt: DateTime.tryParse(
        json['agentResponseAt'] as String? ?? '',
      )?.toLocal(),
      status: json['status'] as String? ?? 'published',
      propertyId: json['propertyId'] as String?,
      propertyName: json['propertyName'] as String?,
    );
  }
}

class ReviewMention {
  const ReviewMention({required this.label, required this.count});

  final String label;
  final int count;

  factory ReviewMention.fromJson(Map<String, dynamic> json) => ReviewMention(
    label: json['label'] as String? ?? '',
    count: (json['count'] as num?)?.toInt() ?? 0,
  );
}

class ReviewSummary {
  const ReviewSummary({
    required this.count,
    required this.overall,
    required this.criteria,
    required this.distribution,
    required this.mentions,
  });

  final int count;
  final double overall;
  final Map<String, double> criteria;
  final Map<int, int> distribution;
  final List<ReviewMention> mentions;

  factory ReviewSummary.fromJson(Map<String, dynamic> json) {
    final criteria = json['criteria'] as Map<String, dynamic>? ?? const {};
    final distribution =
        json['distribution'] as Map<String, dynamic>? ?? const {};
    return ReviewSummary(
      count: (json['count'] as num?)?.toInt() ?? 0,
      overall: (json['overall'] as num?)?.toDouble() ?? 0,
      criteria: {
        for (final field in reviewRatingFields)
          field: (criteria[field] as num?)?.toDouble() ?? 0,
      },
      distribution: {
        for (var rating = 1; rating <= 5; rating++)
          rating: (distribution['$rating'] as num?)?.toInt() ?? 0,
      },
      mentions: (json['mentions'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ReviewMention.fromJson)
          .toList(growable: false),
    );
  }
}

class PropertyReviewPage {
  const PropertyReviewPage({
    required this.reviews,
    required this.summary,
    required this.page,
    required this.pages,
    required this.total,
    required this.sort,
  });

  final List<GuestReview> reviews;
  final ReviewSummary summary;
  final int page;
  final int pages;
  final int total;
  final String sort;

  factory PropertyReviewPage.fromJson(Map<String, dynamic> json) {
    final pagination = json['pagination'] as Map<String, dynamic>? ?? const {};
    return PropertyReviewPage(
      reviews: (json['reviews'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(GuestReview.fromJson)
          .toList(growable: false),
      summary: ReviewSummary.fromJson(
        json['summary'] as Map<String, dynamic>? ?? const {},
      ),
      page: (pagination['page'] as num?)?.toInt() ?? 1,
      pages: (pagination['pages'] as num?)?.toInt() ?? 0,
      total: (pagination['total'] as num?)?.toInt() ?? 0,
      sort: pagination['sort'] as String? ?? 'newest',
    );
  }
}

class ReportNote {
  const ReportNote({
    required this.authorRole,
    required this.visibility,
    required this.kind,
    required this.body,
    required this.createdAt,
  });

  final String authorRole;
  final String visibility;
  final String kind;
  final String body;
  final DateTime createdAt;

  factory ReportNote.fromJson(Map<String, dynamic> json) => ReportNote(
    authorRole: json['authorRole'] as String? ?? '',
    visibility: json['visibility'] as String? ?? 'internal',
    kind: json['kind'] as String? ?? 'note',
    body: json['body'] as String? ?? '',
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '')?.toLocal() ??
        DateTime.now(),
  );
}

/// A private problem report, shaped by the viewer's role on the server.
class ProblemReportItem {
  const ProblemReportItem({
    required this.id,
    required this.reference,
    required this.bookingId,
    required this.propertyName,
    required this.category,
    required this.severity,
    required this.description,
    required this.status,
    required this.createdAt,
    required this.notes,
    required this.evidence,
    this.customerName,
    this.classification,
    this.sharedWithAgent = false,
  });

  final String id;
  final String reference;
  final String bookingId;
  final String propertyName;
  final String category;
  final String severity;
  final String description;
  final String status;
  final DateTime createdAt;
  final List<ReportNote> notes;
  final List<String> evidence;
  final String? customerName;
  final String? classification;
  final bool sharedWithAgent;

  bool get isUrgent => severity == 'urgent';
  bool get isSensitive => classification == 'sensitive';
  bool get isFinished => status == 'resolved' || status == 'closed';

  factory ProblemReportItem.fromJson(Map<String, dynamic> json) {
    final customer = json['customer'] as Map<String, dynamic>?;
    return ProblemReportItem(
      id: json['id'] as String? ?? '',
      reference: json['reference'] as String? ?? '',
      bookingId: json['bookingId'] as String? ?? '',
      propertyName: json['propertyName'] as String? ?? 'Property',
      category: json['category'] as String? ?? 'other',
      severity: json['severity'] as String? ?? 'general',
      description: json['description'] as String? ?? '',
      status: json['status'] as String? ?? 'open',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
      notes: (json['notes'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ReportNote.fromJson)
          .toList(growable: false),
      evidence: (json['evidence'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      customerName:
          customer?['fullName'] as String? ?? json['customerName'] as String?,
      classification: json['visibilityClassification'] as String?,
      sharedWithAgent: json['sharedWithAgent'] as bool? ?? false,
    );
  }
}
