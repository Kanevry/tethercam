/* TetherCam - tethercam.app
   Jobs: entry-only scroll reveal, the copy button, and an optional release-
   version check. No dependencies. */
(function () {
  "use strict";

  var doc = document;
  doc.documentElement.classList.add("js");

  var reduce = window.matchMedia &&
    window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  var items = doc.querySelectorAll("[data-reveal]");
  var arch = doc.getElementById("arch-diagram");

  function showAll() {
    for (var i = 0; i < items.length; i++) items[i].classList.add("is-in");
    if (arch) arch.classList.add("is-playing");
  }

  if (reduce || !("IntersectionObserver" in window)) {
    showAll();
  } else {
    var io = new IntersectionObserver(function (entries) {
      for (var i = 0; i < entries.length; i++) {
        var e = entries[i];
        var tall = e.boundingClientRect.height > window.innerHeight * 0.7;
        if (!e.isIntersecting || (e.intersectionRatio < 0.15 && !tall)) continue;
        e.target.classList.add("is-in");
        io.unobserve(e.target);
      }
    }, { threshold: [0, 0.15], rootMargin: "0px 0px -40px 0px" });

    for (var i = 0; i < items.length; i++) io.observe(items[i]);

    if (arch) {
      var ao = new IntersectionObserver(function (entries) {
        for (var j = 0; j < entries.length; j++) {
          if (!entries[j].isIntersecting) continue;
          entries[j].target.classList.add("is-playing");
          ao.unobserve(entries[j].target);
        }
      }, { threshold: 0.25 });
      ao.observe(arch);
    }
  }

  var buttons = doc.querySelectorAll("[data-copy]");
  for (var k = 0; k < buttons.length; k++) {
    buttons[k].addEventListener("click", function () {
      var btn = this;
      var src = doc.getElementById(btn.getAttribute("data-copy"));
      if (!src || !navigator.clipboard) return;
      navigator.clipboard.writeText(src.textContent.trim()).then(function () {
        btn.textContent = "Copied";
        window.setTimeout(function () { btn.textContent = "Copy"; }, 1600);
      });
    });
  }

  // Release check: the download buttons default to the honest "not released
  // yet" copy. If a real GitHub release with the plugin asset shows up,
  // swap in the version. Any failure (offline, rate limit, CSP) leaves the
  // default text in place.
  if (window.fetch) {
    fetch("https://api.github.com/repos/Kanevry/tethercam/releases/latest", {
      headers: { Accept: "application/vnd.github+json" }
    }).then(function (res) {
      return res.ok ? res.json() : null;
    }).then(function (release) {
      if (!release || release.draft || release.prerelease || !release.tag_name) return;
      var assets = release.assets || [];
      var hasPkg = false;
      for (var i = 0; i < assets.length; i++) {
        if (assets[i].name === "TetherCam-obs-plugin.pkg") { hasPkg = true; break; }
      }
      if (!hasPkg) return;

      var tag = release.tag_name.replace(/^v/i, "");
      var label = "v" + tag;
      var pkgSubs = doc.querySelectorAll('[data-release="pkg"]');
      for (var p = 0; p < pkgSubs.length; p++) pkgSubs[p].textContent = label + ", macOS 12+";
      var zipSubs = doc.querySelectorAll('[data-release="zip"]');
      for (var z = 0; z < zipSubs.length; z++) zipSubs[z].textContent = label + ", unsigned bundle";
    }).catch(function () {});
  }
})();
