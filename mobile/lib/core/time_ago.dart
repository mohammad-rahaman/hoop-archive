/// A compact relative-time label, e.g. "just now", "5m ago", "3h ago",
/// "2d ago", falling back to an ISO date for anything older than a month.
String relativeSince(DateTime when) {
  final diff = DateTime.now().toUtc().difference(when.toUtc());
  if (diff.isNegative || diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 30) return '${diff.inDays}d ago';
  final local = when.toLocal();
  final mm = local.month.toString().padLeft(2, '0');
  final dd = local.day.toString().padLeft(2, '0');
  return '${local.year}-$mm-$dd';
}
