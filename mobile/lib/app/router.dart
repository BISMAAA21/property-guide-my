import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/application/auth_controller.dart';
import '../features/auth/domain/auth_snapshot.dart';
import '../features/auth/presentation/account_problem_screen.dart';
import '../features/auth/presentation/auth_loading_screen.dart';
import '../features/auth/presentation/firebase_setup_screen.dart';
import '../features/auth/presentation/forgot_password_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/register_screen.dart';
import '../features/agreements/presentation/agreement_simplification_screen.dart';
import '../features/damage_detection/presentation/damage_detection_screen.dart';
import '../features/administration/presentation/admin_dashboard_screen.dart';
import '../features/administration/presentation/agent_profile_screen.dart';
import '../features/inspections/presentation/damage_handoff_screen.dart';
import '../features/inspections/presentation/inspection_checklist_screen.dart';
import '../features/inspections/presentation/inspection_home_screen.dart';
import '../features/inspections/presentation/inspection_summary_screen.dart';
import '../features/image_verification/presentation/image_verification_screen.dart';
import '../features/properties/presentation/agent_property_dashboard_screen.dart';
import '../features/properties/presentation/property_detail_screen.dart';
import '../features/properties/presentation/property_form_screen.dart';
import '../features/properties/presentation/student_property_detail_screen.dart';
import '../features/properties/presentation/student_property_search_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authControllerProvider);
  return GoRouter(
    initialLocation: '/loading',
    refreshListenable: auth,
    redirect: (context, state) => _redirect(auth.snapshot, state.uri.path),
    routes: [
      GoRoute(
        path: '/loading',
        builder: (context, state) => const AuthLoadingScreen(),
      ),
      GoRoute(
        path: '/setup',
        builder: (context, state) =>
            FirebaseSetupScreen(errorMessage: auth.snapshot.message),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/account-problem',
        builder: (context, state) => const AccountProblemScreen(),
      ),
      GoRoute(
        path: '/student',
        builder: (context, state) => const StudentPropertySearchScreen(),
      ),
      GoRoute(
        path: '/student/agreements',
        builder: (context, state) => const AgreementSimplificationScreen(),
      ),
      GoRoute(
        path: '/student/properties/:propertyId',
        builder: (context, state) => StudentPropertyDetailScreen(
          propertyId: state.pathParameters['propertyId']!,
        ),
      ),
      GoRoute(
        path: '/student/properties/:propertyId/verify',
        builder: (context, state) => ImageVerificationScreen(
          propertyId: state.pathParameters['propertyId']!,
        ),
      ),
      GoRoute(
        path: '/student/properties/:propertyId/damage',
        builder: (context, state) => DamageDetectionScreen(
          propertyId: state.pathParameters['propertyId']!,
        ),
      ),
      GoRoute(
        path: '/student/properties/:propertyId/inspection',
        builder: (context, state) => InspectionHomeScreen(
          propertyId: state.pathParameters['propertyId']!,
        ),
      ),
      GoRoute(
        path:
            '/student/properties/:propertyId/inspection/:inspectionId/summary',
        builder: (context, state) => InspectionSummaryScreen(
          propertyId: state.pathParameters['propertyId']!,
          inspectionId: state.pathParameters['inspectionId']!,
        ),
      ),
      GoRoute(
        path: '/student/properties/:propertyId/inspection/:inspectionId/damage',
        builder: (context, state) => DamageHandoffScreen(
          propertyId: state.pathParameters['propertyId']!,
          inspectionId: state.pathParameters['inspectionId']!,
          checkId: state.uri.queryParameters['checkId'] ?? '',
          photoPath: state.uri.queryParameters['photoPath'] ?? '',
          photoUrl: state.uri.queryParameters['photoUrl'] ?? '',
        ),
      ),
      GoRoute(
        path: '/student/properties/:propertyId/inspection/:inspectionId',
        builder: (context, state) => InspectionChecklistScreen(
          propertyId: state.pathParameters['propertyId']!,
          inspectionId: state.pathParameters['inspectionId']!,
        ),
      ),
      GoRoute(
        path: '/agent',
        builder: (context, state) => const AgentPropertyDashboardScreen(),
      ),
      GoRoute(
        path: '/agent/profile',
        builder: (context, state) => const AgentProfileScreen(),
      ),
      GoRoute(
        path: '/agent/properties/new',
        builder: (context, state) => const PropertyFormScreen(),
      ),
      GoRoute(
        path: '/agent/properties/:propertyId/edit',
        builder: (context, state) =>
            PropertyFormScreen(propertyId: state.pathParameters['propertyId']!),
      ),
      GoRoute(
        path: '/agent/properties/:propertyId',
        builder: (context, state) => PropertyDetailScreen(
          propertyId: state.pathParameters['propertyId']!,
        ),
      ),
      GoRoute(
        path: '/admin',
        builder: (context, state) => const AdminDashboardScreen(),
      ),
      GoRoute(
        path: '/admin/properties/:propertyId',
        builder: (context, state) => PropertyDetailScreen(
          propertyId: state.pathParameters['propertyId']!,
        ),
      ),
    ],
  );
});

String? _redirect(AuthSnapshot snapshot, String location) {
  final isAuthRoute = {
    '/login',
    '/register',
    '/forgot-password',
  }.contains(location);

  return switch (snapshot.status) {
    AuthSnapshotStatus.loading => location == '/loading' ? null : '/loading',
    AuthSnapshotStatus.configurationRequired =>
      location == '/setup' ? null : '/setup',
    AuthSnapshotStatus.signedOut => isAuthRoute ? null : '/login',
    AuthSnapshotStatus.missingProfile ||
    AuthSnapshotStatus.disabled ||
    AuthSnapshotStatus.failure =>
      location == '/account-problem' ? null : '/account-problem',
    AuthSnapshotStatus.authenticated =>
      (location == snapshot.user!.role.homeLocation ||
              location.startsWith('${snapshot.user!.role.homeLocation}/'))
          ? null
          : snapshot.user!.role.homeLocation,
  };
}
