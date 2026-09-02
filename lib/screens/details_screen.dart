import 'package:flutter/material.dart';
import '../widgets/app_scope.dart';
import '../widgets/app_shell_scaffold.dart';

class DetailsScreen extends StatelessWidget {
  const DetailsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final item = c.selectedItem;
    if (item == null) return const SizedBox.shrink();
    return AppShellScaffold(
      showBack: true,
      title: item.title,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(40, 8, 40, 28),
        child: Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.group),
                const SizedBox(height: 10),
                Text(
                  item.description.isEmpty
                      ? 'No description available yet.'
                      : item.description,
                ),
                const SizedBox(height: 10),
                SelectableText(item.streamUrl),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: c.openPlayer,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Play selected stream'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
