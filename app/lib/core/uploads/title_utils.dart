String? deriveUploadTitle(String? rawTitle) {
  final trimmed = rawTitle?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }

  if (_isGenericTitle(trimmed)) {
    return null;
  }

  return trimmed;
}

bool _isGenericTitle(String title) {
  final lower = title.toLowerCase();

  const genericStarts = [
    'recording',
    'audio recording',
    'voice memo',
    'memo',
    'new recording',
    'untitled',
    'meeting recording',
    'abstract',
  ];

  for (final prefix in genericStarts) {
    if (lower == prefix || lower.startsWith(prefix + ' ')) {
      return true;
    }
  }

  final alphanumeric = lower.replaceAll(RegExp(r'[^a-z0-9]'), '');
  if (alphanumeric.isEmpty) {
    return true;
  }

  // Titles that are mostly digits (e.g. timestamps like 20240601_123456)
  if (RegExp(r'^\d{6,}$').hasMatch(alphanumeric)) {
    return true;
  }

  // Single short word titles offer little context (e.g. "abstract")
  if (!lower.contains(' ') && lower.length <= 8) {
    return true;
  }

  return false;
}
