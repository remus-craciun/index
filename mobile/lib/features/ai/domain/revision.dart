/// One line of a revision preview.
class PlanChange {
  const PlanChange({required this.kind, required this.action, required this.title, this.detail});

  final String kind; // plan, milestone, task
  final String action; // added, removed, updated, moved
  final String title;
  final String? detail;

  factory PlanChange.fromJson(Map<String, dynamic> j) => PlanChange(
        kind: j['kind'] as String,
        action: j['action'] as String,
        title: j['title'] as String,
        detail: j['detail'] as String?,
      );
}

/// What a follow-up request would do to a plan. [revision] is sent back
/// unchanged to apply it.
class RevisionProposal {
  const RevisionProposal({required this.revision, required this.summary, required this.changes, required this.minutesPerDay});

  final Map<String, dynamic> revision;
  final String summary;
  final List<PlanChange> changes;
  final int minutesPerDay;

  factory RevisionProposal.fromJson(Map<String, dynamic> j) => RevisionProposal(
        revision: (j['revision'] as Map).cast<String, dynamic>(),
        summary: (j['summary'] as String?) ?? '',
        changes: ((j['changes'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(PlanChange.fromJson)
            .toList(),
        minutesPerDay: (j['minutes_per_day'] as num?)?.toInt() ?? 60,
      );

  bool get isEmpty => changes.isEmpty;
}
