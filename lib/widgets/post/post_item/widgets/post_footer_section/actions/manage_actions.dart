// ignore_for_file: invalid_use_of_protected_member

part of '../post_footer_section.dart';

extension _PostFooterManageActions on _PostFooterSectionState {
  Future<void> _toggleSolution() async {
    if (_isTogglingAnswer) return;

    HapticFeedback.lightImpact();
    setState(() => _isTogglingAnswer = true);

    try {
      if (_isAcceptedAnswer) {
        await _service.unacceptAnswer(widget.post.id);
        if (mounted) {
          setState(() => _isAcceptedAnswer = false);
          widget.onAcceptedAnswerChanged?.call(false);
          widget.onSolutionChanged?.call(widget.post.id, false);
          ToastService.showSuccess(S.current.post_solutionUnaccepted);
        }
      } else {
        await _service.acceptAnswer(widget.post.id);
        if (mounted) {
          setState(() => _isAcceptedAnswer = true);
          widget.onAcceptedAnswerChanged?.call(true);
          widget.onSolutionChanged?.call(widget.post.id, true);
          ToastService.showSuccess(S.current.post_solutionAccepted);
        }
      }
    } on DioException catch (_) {
      // 网络错误已由 ErrorInterceptor 处理
    } catch (e, s) {
      AppErrorHandler.handleUnexpected(e, s);
    } finally {
      if (mounted) {
        setState(() => _isTogglingAnswer = false);
      }
    }
  }

  Future<void> _deletePost() async {
    if (_isDeleting) return;
    HapticFeedback.lightImpact();
    setState(() => _isDeleting = true);

    try {
      await _service.deletePost(widget.post.id);
      if (mounted) {
        ToastService.showSuccess(S.current.common_deleted);
        widget.onRefreshPost?.call(widget.post.id);
      }
    } on DioException catch (_) {
      // 网络错误已由 ErrorInterceptor 处理
    } catch (e, s) {
      AppErrorHandler.handleUnexpected(e, s);
    } finally {
      if (mounted) {
        setState(() => _isDeleting = false);
      }
    }
  }

  Future<void> _recoverPost() async {
    if (_isDeleting) return;
    HapticFeedback.lightImpact();
    setState(() => _isDeleting = true);

    try {
      await _service.recoverPost(widget.post.id);
      if (mounted) {
        ToastService.showSuccess(S.current.common_restored);
        widget.onRefreshPost?.call(widget.post.id);
      }
    } on DioException catch (_) {
      // 网络错误已由 ErrorInterceptor 处理
    } catch (e, s) {
      AppErrorHandler.handleUnexpected(e, s);
    } finally {
      if (mounted) {
        setState(() => _isDeleting = false);
      }
    }
  }
}
