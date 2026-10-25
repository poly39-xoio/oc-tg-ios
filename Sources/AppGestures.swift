import Foundation
import WebKit

/// App-only gesture layer.
///
/// 1. Blocks the web client's chat-folders sidebar, which opens on a 10px
///    horizontal drift, so a slightly sloppy tap on a chat row no longer jumps
///    to the folders page.
/// 2. Adds per-row swipe actions (left: archive/delete, right: read/pin) that
///    only engage after a deliberate 30px horizontal move, so taps stay taps.
enum AppGestures {
    static func makeScript() -> WKUserScript {
        WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
    }

    private static let source = #"""
    (function () {
      if (window.__ocGestures) return;
      window.__ocGestures = true;

      var LOCK_PX = 30;
      var OPEN_X = 132;
      var LEFT_ACTIONS = [
        { label: '封存', color: '#3F4A54', match: ['Archive', '封存', '归档', '歸檔'] },
        { label: '刪除', color: '#C0392B', match: ['Delete', '刪除', '删除'] }
      ];
      var RIGHT_ACTIONS = [
        { label: '已讀', color: '#3F4A54', match: ['Mark as read', '標為已讀', '标记为已读', '已讀'] },
        { label: '置頂', color: '#3F4A54', match: ['Pin', '置頂', '置顶'] }
      ];

      function clickMenuAction(names) {
        var items = document.querySelectorAll('.MenuItem, [class*="MenuItem"], [class*="menu-item"]');
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
        (row.querySelector('.ChatInfo, .info, .avatar-wrapper') || row).dispatchEvent(ev);
        window.setTimeout(function () {
          if (!clickMenuAction(names)) {
            row.dispatchEvent(ev);
            window.setTimeout(function () { clickMenuAction(names); }, 260);
          }
        }, 260);
      }

      function makeRail(actions, side) {
        var rail = document.createElement('div');
        rail.setAttribute('data-oc-rail', side);
        rail.style.cssText = 'position:absolute;top:0;bottom:0;display:none;z-index:3;'
          + (side === 'right' ? 'right:0;' : 'left:0;');
        actions.forEach(function (a) {
          var b = document.createElement('button');
          b.type = 'button';
          b.textContent = a.label;
          b.style.cssText = 'border:0;margin:0;padding:0 16px;height:100%;font-size:15px;color:#fff;background:' + a.color + ';';
          b.addEventListener('click', function (e) {
            e.preventDefault(); e.stopPropagation();
            closeRow(row);
            openRowMenu(row, a.match);
          });
          rail.appendChild(b);
        });
        return rail;
      }

      var row = null, railL = null, railR = null;
      var sx = 0, sy = 0, locked = false, moved = false;

      function prepare(r) {
        if (r === row) return;
        cleanup();
        row = r;
        if (getComputedStyle(r).position === 'static') r.style.position = 'relative';
        r.style.overflow = 'hidden';
        railR = makeRail(LEFT_ACTIONS, 'right');
        railL = makeRail(RIGHT_ACTIONS, 'left');
        r.appendChild(railR);
        r.appendChild(railL);
      }

      function closeRow(r) {
        if (!r) return;
        r.style.transition = 'transform 150ms ease';
        r.style.transform = '';
        var rails = r.querySelectorAll('[data-oc-rail]');
        for (var i = 0; i < rails.length; i++) rails[i].style.display = 'none';
        window.setTimeout(function () { r.style.transition = ''; }, 180);
      }

      function cleanup() {
        if (row) {
          var rails = row.querySelectorAll('[data-oc-rail]');
          for (var i = 0; i < rails.length; i++) rails[i].parentNode.removeChild(rails[i]);
          row.style.transform = '';
          row.style.overflow = '';
        }
        row = null; railL = null; railR = null;
      }

      document.addEventListener('touchstart', function (e) {
        if (e.touches.length !== 1) return;
        var target = e.target;
        var listRow = target && target.closest ? target.closest('.ListItem-button') : null;
        if (!listRow || listRow.closest('.messages-container, .Message')) { row = null; return; }
        sx = e.touches[0].clientX; sy = e.touches[0].clientY;
        locked = false; moved = false;
        prepare(listRow);
      }, { capture: true, passive: true });

      document.addEventListener('touchmove', function (e) {
        if (!row || e.touches.length !== 1) return;
        var dx = e.touches[0].clientX - sx;
        var dy = e.touches[0].clientY - sy;
        if (!locked) {
          if (Math.abs(dx) > LOCK_PX && Math.abs(dx) > Math.abs(dy) * 2) {
            locked = true;
            railR.style.display = dx < 0 ? 'flex' : 'none';
            railL.style.display = dx > 0 ? 'flex' : 'none';
          } else {
            return;
          }
        }
        // Own the gesture: stops the client's 10px folders-sidebar swipe.
        e.stopPropagation();
        e.preventDefault();
        moved = true;
        row.style.transform = 'translateX(' + Math.max(-OPEN_X, Math.min(OPEN_X, dx)) + 'px)';
      }, { capture: true, passive: false });

      document.addEventListener('touchend', function () {
        if (!row) return;
        if (!locked) { return; }
        var m = /translateX\((-?[\d.]+)px\)/.exec(row.style.transform || '');
        var cur = m ? parseFloat(m[1]) : 0;
        var need = Math.max(72, row.getBoundingClientRect().width * 0.35);
        if (cur < -need) row.style.transform = 'translateX(-' + OPEN_X + 'px)';
        else if (cur > need) row.style.transform = 'translateX(' + OPEN_X + 'px)';
        else closeRow(row);
        locked = false; moved = false;
      }, { capture: true, passive: true });

      /* Make sure the last message is never hidden behind the composer. */
      function reserveComposer() {
        var c = document.querySelector('.Composer');
        if (!c) return;
        var h = Math.ceil(c.getBoundingClientRect().height);
        if (!h) return;
        var lists = document.querySelectorAll('.messages-container, .MessageList, .chat .MessageList');
        for (var i = 0; i < lists.length; i++) lists[i].style.setProperty('padding-bottom', (h + 16) + 'px', 'important');
      }
      window.addEventListener('load', reserveComposer);
      window.setInterval(reserveComposer, 2500);
    })();
    """#
}
