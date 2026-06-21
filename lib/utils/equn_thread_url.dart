class EqunThreadUrl {
  EqunThreadUrl._();

  static String thread(int tid, {int page = 1}) {
    return 'https://equn.com/forum/thread-$tid-$page-1.html';
  }
}
