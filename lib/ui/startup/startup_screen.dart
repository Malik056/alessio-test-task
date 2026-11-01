import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/auth_repository.dart';
import '../login/login_screen.dart';
import '../products/product_list_screen.dart';

/// Shown while the stored session is checked (and refreshed if expired),
/// then replaced by the list or the login screen. Usually instant: the
/// network is only hit when the access token has expired.
class StartupScreen extends StatefulWidget {
  const StartupScreen({super.key});

  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen> {
  @override
  void initState() {
    super.initState();
    _route();
  }

  Future<void> _route() async {
    final loggedIn = await context.read<AuthRepository>().restoreSession();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      loggedIn ? ProductListScreen.route() : LoginScreen.route(),
    );
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}
