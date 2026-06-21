import 'dart:convert';

class EqunDiscuzAuth {
  EqunDiscuzAuth._();

  static const String loginUrl =
      'https://equn.com/forum/member.php?mod=logging&action=login';
  static const String lostPasswordUrl =
      'https://equn.com/forum/member.php?mod=lostpasswd';
  static const String registerUrl =
      'https://equn.com/forum/member.php?mod=2wdqwe';

  static const Set<String> sessionCookieNames = {
    'mp49_2132_auth',
    'mp49_2132_saltkey',
    'mp49_2132_lastact',
    'mp49_2132_lastvisit',
  };

  static String buildAutoLoginScript({
    required String username,
    required String password,
    required bool remember,
  }) {
    final encodedUsername = jsonEncode(username);
    final encodedPassword = jsonEncode(password);
    final encodedRemember = remember ? 'true' : 'false';

    return '''
(function() {
  var username = $encodedUsername;
  var password = $encodedPassword;
  var remember = $encodedRemember;
  if (!username || !password || window.__equnDiscuzAutoLoginSubmitted) return;

  function visible(el) {
    if (!el) return false;
    var rect = el.getBoundingClientRect();
    return rect.width > 0 && rect.height > 0;
  }

  function findLoginForm() {
    var forms = Array.prototype.slice.call(document.querySelectorAll('form'));
    return forms.find(function(form) {
      var action = form.getAttribute('action') || '';
      return action.indexOf('member.php') !== -1 &&
        action.indexOf('mod=logging') !== -1 &&
        action.indexOf('action=login') !== -1 &&
        form.querySelector('input[name="username"]') &&
        form.querySelector('input[name="password"]');
    }) || document.querySelector('form[id^="loginform"]') || document.forms.login;
  }

  function setValue(input, value) {
    if (!input) return;
    input.focus();
    input.value = value;
    input.dispatchEvent(new Event('input', { bubbles: true }));
    input.dispatchEvent(new Event('change', { bubbles: true }));
  }

  function hasCaptcha(form) {
    return !!(
      form.querySelector('input[name="seccodeverify"]') ||
      form.querySelector('input[id^="seccodeverify"]') ||
      form.querySelector('[id^="seccode_"]') ||
      form.querySelector('.seccode')
    );
  }

  function submitDiscuzLogin() {
    var form = findLoginForm();
    if (!form || !visible(form)) return false;

    var userInput = form.querySelector('input[name="username"]');
    var passInput = form.querySelector('input[name="password"]');
    if (!userInput || !passInput) return false;

    setValue(userInput, username);
    setValue(passInput, password);

    var loginField =
      form.querySelector('select[name="loginfield"]') ||
      form.querySelector('select[name="fastloginfield"]');
    if (loginField) {
      loginField.value = username.indexOf('@') === -1 ? 'username' : 'email';
      loginField.dispatchEvent(new Event('change', { bubbles: true }));
    }

    var cookieTime = form.querySelector('input[name="cookietime"]');
    if (cookieTime) {
      cookieTime.checked = !!remember;
      cookieTime.value = remember ? '2592000' : '0';
      cookieTime.dispatchEvent(new Event('change', { bubbles: true }));
    }

    if (hasCaptcha(form)) {
      window.__equnDiscuzAutoLoginSubmitted = true;
      return true;
    }

    window.__equnDiscuzAutoLoginSubmitted = true;
    var button =
      form.querySelector('button[name="loginsubmit"]') ||
      form.querySelector('button[type="submit"]') ||
      form.querySelector('input[type="submit"]');
    if (button) {
      button.click();
    } else if (typeof form.requestSubmit === 'function') {
      form.requestSubmit();
    } else {
      form.submit();
    }
    return true;
  }

  if (submitDiscuzLogin()) return;
  var attempts = 0;
  var timer = setInterval(function() {
    if (submitDiscuzLogin() || ++attempts > 40) clearInterval(timer);
  }, 250);
})();
''';
  }

  static const String readCurrentProfileScript = '''
(function() {
  try {
    function clean(text) {
      text = (text || '').trim();
      text = text.replace(/^访问我的空间[:：]?/, '').trim();
      if (!text || text === '退出' || text === '设置' || text === '消息' || text === '我的帖子') return '';
      return text;
    }

    function absUrl(url) {
      if (!url) return null;
      try { return new URL(url, location.href).href; } catch (e) { return url; }
    }

    function uidFromHref(href) {
      if (!href) return null;
      var match = href.match(/[?&]uid=(\\d+)/) || href.match(/space-uid-(\\d+)/);
      return match ? parseInt(match[1], 10) : null;
    }

    function avatarFromScope(scope, uid) {
      if (!scope) return uid ? absUrl('uc_server/avatar.php?uid=' + uid + '&size=middle') : null;
      var avatarImg = scope.querySelector(
        '.avt img, img[src*="avatar.php?uid="], a[href*="home.php?mod=space"] img, a[href*="space-uid-"] img'
      );
      if (avatarImg) {
        return absUrl(avatarImg.getAttribute('src'));
      }
      return uid ? absUrl('uc_server/avatar.php?uid=' + uid + '&size=middle') : null;
    }

    function profileFromScope(scope, fallbackUid) {
      if (!scope) return null;
      var selectors = [
        '.vwmy a[href*="home.php?mod=space"]',
        'a.vwmy[href*="home.php?mod=space"]',
        'a[href*="home.php?mod=space"][title*="空间"]',
        'a[href*="space-uid-"]',
        'a[href*="home.php?mod=space"]'
      ];
      var username = '';
      var uid = fallbackUid || null;
      for (var s = 0; s < selectors.length; s++) {
        var links = Array.prototype.slice.call(scope.querySelectorAll(selectors[s]));
        for (var i = 0; i < links.length; i++) {
          var link = links[i];
          var text = clean(link.textContent || link.getAttribute('title') || '');
          var linkUid = uidFromHref(link.getAttribute('href') || '');
          if (linkUid) uid = uid || linkUid;
          if (text) {
            username = text;
            break;
          }
        }
        if (username) break;
      }
      var avatarUrl = avatarFromScope(scope, uid);
      if (username || uid) {
        return {
          username: username || String(uid),
          nickname: username || null,
          uid: uid || null,
          avatar_url: avatarUrl
        };
      }
      return null;
    }

    var uid = null;
    if (typeof discuz_uid !== 'undefined' && String(discuz_uid) !== '0') {
      uid = parseInt(String(discuz_uid), 10);
    }

    var userMenu = document.querySelector('#um');
    var menuProfile = profileFromScope(userMenu, uid);
    if (menuProfile) return JSON.stringify(menuProfile);

    if (typeof discuz_uid !== 'undefined' && String(discuz_uid) !== '0') {
      return JSON.stringify({
        username: String(discuz_uid),
        uid: uid || null,
        avatar_url: avatarFromScope(userMenu, uid)
      });
    }

    var logout = document.querySelector('a[href*="member.php?mod=logging&action=logout"]');
    if (logout) {
      var logoutScope =
        (logout.closest && (logout.closest('#um') || logout.closest('.y'))) ||
        logout.parentElement;
      var logoutProfile = profileFromScope(logoutScope, uid);
      if (logoutProfile) return JSON.stringify(logoutProfile);
    }
    return null;
  } catch (e) {
    return null;
  }
})();
''';

  static const String readCurrentUsernameScript = readCurrentProfileScript;
}
