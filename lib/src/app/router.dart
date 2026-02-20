import 'package:alera/src/features/session/presentation/session_page.dart';
import 'package:go_router/go_router.dart';

GoRouter buildRouter() {
  return GoRouter(
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (context, state) => const SessionPage(),
      ),
    ],
  );
}
