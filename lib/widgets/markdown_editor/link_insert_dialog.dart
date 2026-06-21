import 'package:flutter/material.dart';
import '../../../../../l10n/s.dart';
import '../../utils/dialog_utils.dart';

/// 链接插入对话框
/// 返回 {text: '链接文本', url: 'https://...'}
class LinkInsertDialog extends StatefulWidget {
  final String? initialText;
  final String? initialUrl;

  const LinkInsertDialog({
    super.key,
    this.initialText,
    this.initialUrl,
  });

  @override
  State<LinkInsertDialog> createState() => _LinkInsertDialogState();
}

class _LinkInsertDialogState extends State<LinkInsertDialog> {
  late final TextEditingController _textController;
  late final TextEditingController _urlController;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.initialText);
    _urlController = TextEditingController(text: widget.initialUrl);
  }

  @override
  void dispose() {
    _textController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.of(context).pop({
        'text': _textController.text,
        'url': _urlController.text,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(S.current.link_insertTitle),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _textController,
              decoration: InputDecoration(
                labelText: S.current.link_textLabel,
                hintText: S.current.link_textHint,
                border: OutlineInputBorder(),
              ),
              autofocus: true,
              textInputAction: TextInputAction.next,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return S.current.link_textRequired;
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _urlController,
              decoration: InputDecoration(
                labelText: 'URL',
                hintText: 'https://example.com',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return S.current.link_urlRequired;
                }
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(S.current.common_cancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(S.current.common_confirm),
        ),
      ],
    );
  }
}

/// 显示链接插入对话框
Future<Map<String, String>?> showLinkInsertDialog(
  BuildContext context, {
  String? initialText,
  String? initialUrl,
}) {
  return showAppDialog<Map<String, String>>(
    context: context,
    builder: (context) => LinkInsertDialog(
      initialText: initialText,
      initialUrl: initialUrl,
    ),
  );
}
