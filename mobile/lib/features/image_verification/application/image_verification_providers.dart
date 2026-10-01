import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/bootstrap.dart';
import '../data/firebase_image_verification_repository.dart';
import '../data/unavailable_image_verification_repository.dart';
import '../domain/image_verification_repository.dart';

final imageVerificationRepositoryProvider =
    Provider<ImageVerificationRepository>((ref) {
      final bootstrap = ref.watch(firebaseBootstrapProvider);
      return bootstrap.isReady
          ? FirebaseImageVerificationRepository()
          : const UnavailableImageVerificationRepository();
    });
