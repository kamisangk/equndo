import 'package:flutter/material.dart';
import '../common/skeleton.dart';

/// 话题列表骨架屏
class TopicListSkeleton extends StatelessWidget {
  final EdgeInsetsGeometry padding;

  const TopicListSkeleton({
    super.key,
    this.padding = const EdgeInsets.all(12),
  });

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      child: ListView.builder(
        padding: padding,
        itemCount: 8,
        itemBuilder: (context, index) => const _TopicCardSkeleton(),
      ),
    );
  }
}

/// 单个话题卡片的骨架屏 — 匹配紧凑横向布局
class _TopicCardSkeleton extends StatelessWidget {
  const _TopicCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 左侧：头像骨架
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: SkeletonCircle(size: 34),
            ),
            const SizedBox(width: 10),
            // 右侧：两行内容
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 第1行：标题
                  SkeletonBox(width: double.infinity, height: 18),
                  const SizedBox(height: 4),
                  SkeletonBox(width: 160, height: 18),
                  const SizedBox(height: 8),
                  // 第2行：分类标签 + 时间
                  Row(
                    children: [
                      SkeletonBox(width: 60, height: 16, borderRadius: 4),
                      const SizedBox(width: 6),
                      SkeletonBox(width: 40, height: 16, borderRadius: 4),
                      const Spacer(),
                      SkeletonBox(width: 50, height: 14),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
