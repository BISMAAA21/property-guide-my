import 'package:flutter/material.dart';

import '../../damage_detection/presentation/damage_detection_screen.dart';

class DamageHandoffScreen extends StatelessWidget {
  const DamageHandoffScreen({
    required this.propertyId,
    required this.inspectionId,
    required this.checkId,
    required this.photoPath,
    required this.photoUrl,
    super.key,
  });

  final String propertyId;
  final String inspectionId;
  final String checkId;
  final String photoPath;
  final String photoUrl;

  @override
  Widget build(BuildContext context) {
    return DamageDetectionScreen(
      propertyId: propertyId,
      inspectionId: inspectionId,
      checkId: checkId,
      photoPath: photoPath,
      photoUrl: photoUrl,
    );
  }
}
