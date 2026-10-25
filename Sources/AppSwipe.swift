import Foundation
import WebKit

/// Chat-list swipe actions — **app only** (the web build is untouched).
///
/// The web client has no per-row swipe gestures, so the shell injects this
/// script. A horizontal drag over a chat row reveals two buttons; tapping one
/// opens the row's ordinary context menu and clicks the matching entry, so the
/// action still runs through the client's own code path.
enum AppSwipe {
    static func makeScript() -> WKUserScript {
        WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
    }

    private static let source = #"""
    (function () {
      if (window.__ocSwipeInstalled) return;
      window.__ocSwipeInstalled = true;

      var OPEN_X = 132;
      var LEFT_ACTIONS = [
        { label: '封存', color: '#3F4A54', match: ['Archive', '封存', '归档', '歸檔'] },
        { label: '刪除', color: '#C0392B', match: ['Delete', '刪除', '删除'] }
      ];
      var RIGHT_ACTIONS = [
        { label: '已讀', color: '#3F4A54', match: ['Mark as read', '標為已讀', '标记为已读', '已讀'] },
        { label: '置頂', color: '#3F4A54', match: ['Pin', '置頂', '置顶'] }
      ];

      function menuItems() {
        return Array.prototype.slice.call(document.querySelectorAll('.MenuItem, [class*="MenuItem"], [class*="menu-item"]'));
      }

      function clickMenuAction(names) {
        var items = menuItems();
        for (var i = 0; i < items.length; i++) {
          var text = (items[i].textContent || '').trim();
          for (var n = 0; n < names.length; n++) {
            if (text.indexOf(names[n]) !== -1) { items[i].click(); return true; }
          }
        }
        return false;
      }

      function openRowMenu(row, names) {
        var rect = row.getBoundingClientRect();
        var ev = new MouseEvent('contextmenu', {
          bubbles: true, cancelable: true, view: window,
          clientX: Math.round(rect.left + rect.width / 2),
          clientY: Math.round(rect.top + rect.height / 2)
        });
        var target = row.querySelector('.ChatInfo, .info, .avatar-wrapper') || row;
        target.dispatchEvent(ev);
        window.setTimeout(function () {
          if (!clickMenuAction(names)) {
            row.dispatchEvent(ev);
            window.setTimeout(function () { clickMenuAction(names); }, 250);
          }
        }, 250);
      }

      function makeRail(actions, side) {
        var rail = document.createElement('div');
        rail.setAttribute('data-oc-rail', side);
        rail.style.cssText = 'position:absolute;top:0;bottom:0;display:none;z-index:2;' + (side === 'right' ? 'right:0;' : 'left:0;');
        actions.forEach(function (action) {
          var btn = document.createElement('button');
          btn.type = 'button';
          btn.textContent = action.label;
          btn.style.cssText = 'border:0;margin:0;padding:0 16px;height:100%;font-size:15px;color:#fff;background:' + action.color + ';';
          btn.addEventListener('click', function (e) {
            e.preventDefault();
            e.stopPropagation();
            close(row);
            openRowMenu(row, action.match);
          });
          rail.appendChild(btn);
        });
        return rail;
      }

      function close(row) {
        row.style.transition = 'transform 160ms ease';
        row.style.transform = '';
        var rails = row.querySelectorAll('[data-oc-rail]');
        for (var i = 0; i < rails.length; i++) rails[i].style.display = 'none';
        window.setTimeout(function () { row.style.transition = ''; }, 200);
      }

      function attach(row) {
        if (row.getAttribute('data-oc-bound')) return;
        row.setAttribute('data-oc-bound', '1');
        if (getComputedStyle(row).position === 'static') row.style.position = 'relative';
        row.style.overflow = 'hidden';

        var rightRail = makeRail(LEFT_ACTIONS, 'right');
        var leftRail = makeRail(RIGHT_ACTIONS, 'left');
        row.appendChild(rightRail);
        row.appendChild(leftRail);

        var sx = 0, sy = 0, dragging = false, locked = false;

        row.addEventListener('touchstart', function (e) {
          if (e.touches.length !== 1) return;
          sx = e.touches[0].clientX; sy = e.touches[0].clientY;
          dragging = false; locked = false;
          row.style.transition = '';
        }, { passive: true });

        row.addEventListener('touchmove', function (e) {
          if (e.touches.length !== 1) return;
          var dx = e.touches[0].clientX - sx;
          var dy = e.touches[0].clientY - sy;
          if (!locked) {
            if (Math.abs(dx) > 14 && Math.abs(dx) > Math.abs(dy) * 1.5) {
              locked = true; dragging = true;
              rightRail.style.display = dx < 0 ? 'flex' : 'none';
              leftRail.style.display = dx > 0 ? 'flex' : 'none';
            } else {
              return;
            }
          }
          if (!dragging) return;
          e.preventDefault();
          var shift = Math.max(-OPEN_X, Math.min(OPEN_X, dx));
          row.style.transform = 'translateX(' + shift + 'px)';
        }, { passive: false });

        row.addEventListener('touchend', function () {
          if (!dragging) return;
          dragging = false;
          var m = /translateX\((-?[\d.]+)px\)/.exec(row.style.transform || '');
          var cur = m ? parseFloat(m[1]) : 0;
          row.style.transition = 'transform 160ms ease';
          if (cur < -60) row.style.transform = 'translateX(-' + OPEN_X + 'px)';
          else if (cur > 60) row.style.transform = 'translateX(' + OPEN_X + 'px)';
          else close(row);
        });
      }

      function scan() {
        var nodes = document.querySelectorAll('.ListItem-button');
        for (var i = 0; i < nodes.length; i++) attach(nodes[i]);
      }

      var timer = null;
      function schedule() {
        if (timer) return;
        timer = window.setTimeout(function () { timer = null; scan(); }, 350);
      }

      if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', schedule);
      else schedule();
      window.addEventListener('load', schedule);
      try {
        new MutationObserver(schedule).observe(document.documentElement, { childList: true, subtree: true });
      } catch (e) {}
    })();
    """#
}
