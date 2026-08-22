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
      /* property LISTING pages (portals bot-wall remote readers; we are inside
         the real page, so harvest the floor-plan URLs directly — payload
         {k:'l',...} routes to the live trace pipeline and feeds the community
         listings cache). Keep in lockstep with WF_BOOKMARKLET's listing mode. */
      if (/rightmove\.co|zoopla\.co|onthemarket\.com|primelocation\.com/i.test(location.hostname)) {
        var H = document.documentElement.innerHTML, fp = [], ph = [], S = {};
        var A = function (u) {
          u = String(u).split('\\/').join('/');
          if (u.indexOf('http') === 0 && !S[u] && fp.length < 6) { S[u] = 1; fp.push(u.slice(0, 400)); }
        };
        var re = /https?:\\?\/\\?\/[^"'\s>\\]*(?:floor[-_]?plan|_FLP_)[^"'\s>\\]*\.(?:jpe?g|png|gif|webp)/gi, m;
        while ((m = re.exec(H))) A(m[0]);
        var ix = H.indexOf('floorPlan');
        while (ix >= 0 && fp.length < 6) {
          var w2 = H.slice(ix, ix + 4000), r2 = /\\?"filename\\?":\\?"([0-9a-f]{16,}\.(?:jpe?g|png|gif))/gi, m2;
          while ((m2 = r2.exec(w2))) A('https://lc.zoocdn.com/' + m2[1]);
          ix = H.indexOf('floorPlan', ix + 9);
        }
        var im = document.images, i;
        for (i = 0; i < im.length && ph.length < 10; i++) {
          var s = im[i].currentSrc || im[i].src || '';
          if (/^https?:/.test(s) && im[i].naturalWidth > 350 && !S[s]) { S[s] = 1; ph.push(s.slice(0, 400)); }
        }
        var t2 = document.body ? document.body.innerText : '';
        var am = /([\d,]+(?:\.\d+)?)\s*(?:sq\.?\s?m\b|sqm\b|m²|square met|sq\.?\s?ft|sqft|ft²|square f)/i.exec(t2);
        var pr2 = /([£€][\d,]{4,}(?:\s?pcm)?)/.exec(t2);
        var og3 = document.querySelector('meta[property="og:title"]');
        var q = { k: 'l', u: location.href.slice(0, 500), t: ((og3 && og3.content) || document.title || '').slice(0, 140), fp: fp, ph: ph };
        if (am) q.a = am[0].slice(0, 40);
        if (pr2) q.pr = pr2[1].slice(0, 30);
        args.completionFunction(q);
        return;
      }
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
