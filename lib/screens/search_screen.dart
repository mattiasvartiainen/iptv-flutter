import 'package:flutter/material.dart';

import '../widgets/app_shell_scaffold.dart';

class SearchScreen extends StatelessWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppShellScaffold(
      showBack: true,
      title: 'Search',
      child: Padding(
        padding: EdgeInsets.fromLTRB(40, 8, 40, 28),
        child: Card(
          child: Center(
            child: Text(
              'Search is part of a later phase.\nUse HOME, LIVE TV, MOVIES, and SERIES for this vertical slice.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
