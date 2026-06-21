import 'package:flutter/material.dart';
import 'callout_config.dart';

/// 可折叠的 Callout Widget
class FoldableCallout extends StatefulWidget {
  final CalloutConfig config;
  final Widget titleWidget;
  final Widget contentWidget;
  final bool initiallyExpanded;

  const FoldableCallout({
    super.key,
    required this.config,
    required this.titleWidget,
    required this.contentWidget,
    required this.initiallyExpanded,
  });

  @override
  State<FoldableCallout> createState() => _FoldableCalloutState();
}

class _FoldableCalloutState extends State<FoldableCallout>
    with SingleTickerProviderStateMixin {
  late bool _isExpanded;
  late AnimationController _controller;
  late Animation<double> _iconTurns;
  late Animation<double> _heightFactor;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _iconTurns = Tween<double>(begin: 0.0, end: 0.5).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );
    _heightFactor = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeIn,
    );
    if (_isExpanded) {
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: widget.config.color.withValues(alpha: 0.1),
        border: Border(
          left: BorderSide(
            color: widget.config.color,
            width: 4,
          ),
        ),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(4),
          bottomRight: Radius.circular(4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 可点击的标题栏
          InkWell(
            onTap: _handleTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  Icon(widget.config.icon, size: 18, color: widget.config.color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: widget.titleWidget,
                  ),
                  RotationTransition(
                    turns: _iconTurns,
                    child: Icon(
                      Icons.expand_more,
                      size: 18,
                      color: widget.config.color.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 可折叠的内容
          ClipRect(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Align(
                  alignment: Alignment.topLeft,
                  heightFactor: _heightFactor.value,
                  child: child,
                );
              },
              child: widget.contentWidget,
            ),
          ),
        ],
      ),
    );
  }
}
