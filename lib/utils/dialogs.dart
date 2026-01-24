import 'package:flutter/material.dart';

Future<void> showErrorDialog(BuildContext context, String message, {String title = 'Error'}) {
  // Parse message for bold text markers (text between asterisks)
  final spans = <TextSpan>[];
  final regex = RegExp(r'\*([^*]+)\*');
  int lastIndex = 0;
  
  for (final match in regex.allMatches(message)) {
    // Add text before the match
    if (match.start > lastIndex) {
      spans.add(TextSpan(text: message.substring(lastIndex, match.start)));
    }
    // Add bold text
    spans.add(TextSpan(
      text: match.group(1),
      style: const TextStyle(fontWeight: FontWeight.bold),
    ));
    lastIndex = match.end;
  }
  
  // Add remaining text
  if (lastIndex < message.length) {
    spans.add(TextSpan(text: message.substring(lastIndex)));
  }
  
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: const TextStyle(color: Colors.red)),
      content: RichText(
        text: TextSpan(
          style: const TextStyle(color: Colors.black87, fontSize: 16),
          children: spans.isEmpty ? [TextSpan(text: message)] : spans,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

Future<void> showInfoDialog(BuildContext context, String message, {String title = 'Info'}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
