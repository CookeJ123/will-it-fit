/* WFShare.js — ExtensionPreprocessingJS for the "Add to Will It Fit" share
   extension. This runs INSIDE Safari's page (same trick as the web bookmarklet,
   so shop bot-walls never apply): grab the user's text selection, or windows of
   text around any "…cm" sizes, plus title / og:image / url, and hand the bundle
   to the extension's Swift side via completionFunction.
   Payload mirrors the bookmarklet exactly: {u, t, x, s?, i?}. */
var WFShareClass = function () {};
WFShareClass.prototype = {
  run: function (args) {
    var p = { u: '', t: '', x: '' };
    try {
      var sl = (window.getSelection ? String(window.getSelection()) : '').trim();
      var t = document.body ? document.body.innerText : '';
      var x;
      if (sl.length > 10) {
        x = sl.slice(0, 6000);
        p.s = 1;
      } else {
        var w = [], re = /\d+(?:[.,]\d+)?\s*cm/gi, m, n = 0;
        while ((m = re.exec(t)) && n < 3) {
          var s = Math.max(0, m.index - 500);
          w.push(t.slice(s, Math.min(t.length, m.index + 500)));
          re.lastIndex = m.index + 500;
          n++;
        }
        x = (w.join('\n') || t.slice(0, 3000)).slice(0, 6000);
      }
      var og = document.querySelector('meta[property="og:title"]');
      var oi = document.querySelector('meta[property="og:image"]');
      p.u = location.href.slice(0, 500);
      p.t = ((og && og.content) || document.title || '').slice(0, 120);
      p.x = x;
      if (oi && oi.content && /^https?:/.test(oi.content)) p.i = oi.content.slice(0, 400);
    } catch (e) {
      try { p.u = location.href.slice(0, 500); p.t = (document.title || '').slice(0, 120); } catch (e2) {}
    }
    args.completionFunction(p);
  },
  finalize: function () {}
};
var ExtensionPreprocessingJS = new WFShareClass();
