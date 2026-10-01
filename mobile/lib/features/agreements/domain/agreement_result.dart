enum AgreementExtractionMethod {
  embeddedText('embedded_text', 'Embedded PDF text'),
  ocr('ocr', 'Scanned pages processed with OCR'),
  mixed('mixed', 'Embedded text and OCR');

  const AgreementExtractionMethod(this.storedValue, this.label);

  final String storedValue;
  final String label;

  static AgreementExtractionMethod? fromStoredValue(Object? value) =>
      values.where((method) => method.storedValue == value).firstOrNull;
}

class SimplifiedAgreementClause {
  const SimplifiedAgreementClause({
    required this.id,
    required this.title,
    required this.original,
    required this.simplified,
    required this.importantPoints,
  });

  factory SimplifiedAgreementClause.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final title = json['title'];
    final original = json['original'];
    final simplified = json['simplified'];
    final rawPoints = json['importantPoints'];
    if (id is! String ||
        !RegExp(r'^clause-[1-9][0-9]*$').hasMatch(id) ||
        title is! String ||
        title.trim().isEmpty ||
        original is! String ||
        original.trim().isEmpty ||
        simplified is! String ||
        simplified.trim().isEmpty ||
        simplified.trim() == original.trim() ||
        rawPoints is! List ||
        rawPoints.isEmpty ||
        rawPoints.length > 5 ||
        rawPoints.any(
          (point) =>
              point is! String || point.trim().isEmpty || point.length > 300,
        )) {
      throw const FormatException('Invalid simplified agreement clause.');
    }
    return SimplifiedAgreementClause(
      id: id,
      title: title.trim(),
      original: original.trim(),
      simplified: simplified.trim(),
      importantPoints: List.unmodifiable(
        rawPoints.cast<String>().map((point) => point.trim()),
      ),
    );
  }

  final String id;
  final String title;
  final String original;
  final String simplified;
  final List<String> importantPoints;

  Map<String, Object> toJson() => {
    'id': id,
    'title': title,
    'original': original,
    'simplified': simplified,
    'importantPoints': importantPoints,
  };
}

class AgreementSimplificationResult {
  const AgreementSimplificationResult({
    required this.extractionMethod,
    required this.clauses,
    required this.disclaimer,
    required this.modelId,
  });

  factory AgreementSimplificationResult.fromJson(Map<String, dynamic> json) {
    final method = AgreementExtractionMethod.fromStoredValue(
      json['extractionMethod'],
    );
    final rawClauses = json['clauses'];
    final disclaimer = json['disclaimer'];
    final modelId = json['modelId'];
    if (method == null ||
        rawClauses is! List ||
        rawClauses.isEmpty ||
        rawClauses.length > 100 ||
        rawClauses.any((value) => value is! Map) ||
        disclaimer is! String ||
        !disclaimer.toLowerCase().contains('not legal advice') ||
        modelId is! String ||
        modelId.trim().isEmpty) {
      throw const FormatException('Invalid agreement-simplification response.');
    }
    final clauses = rawClauses
        .map(
          (value) => SimplifiedAgreementClause.fromJson(
            Map<String, dynamic>.from(value as Map),
          ),
        )
        .toList(growable: false);
    for (var index = 0; index < clauses.length; index++) {
      if (clauses[index].id != 'clause-${index + 1}') {
        throw const FormatException(
          'Agreement clauses are missing or out of order.',
        );
      }
    }
    return AgreementSimplificationResult(
      extractionMethod: method,
      clauses: List.unmodifiable(clauses),
      disclaimer: disclaimer.trim(),
      modelId: modelId.trim(),
    );
  }

  final AgreementExtractionMethod extractionMethod;
  final List<SimplifiedAgreementClause> clauses;
  final String disclaimer;
  final String modelId;
}

class AgreementReport {
  const AgreementReport({
    required this.id,
    required this.studentId,
    required this.documentPath,
    required this.filename,
    required this.result,
    required this.createdAt,
  });

  final String id;
  final String studentId;
  final String documentPath;
  final String filename;
  final AgreementSimplificationResult result;
  final DateTime? createdAt;
}

class AgreementPdfInput {
  const AgreementPdfInput({
    required this.byteLength,
    required this.contentType,
  });

  static const maxBytes = 10 * 1024 * 1024;

  final int byteLength;
  final String contentType;

  String? validate() {
    if (byteLength <= 0 || byteLength > maxBytes) {
      return 'Choose a PDF smaller than 10 MiB.';
    }
    if (contentType != 'application/pdf') {
      return 'Choose an English tenancy agreement in PDF format.';
    }
    return null;
  }
}
