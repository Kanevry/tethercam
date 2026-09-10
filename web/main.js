/* TetherCam - tethercam.app
   Jobs: entry-only scroll reveal and the copy button. No dependencies. */
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
      var originalLabel = btn.textContent;
      navigator.clipboard.writeText(src.textContent.trim()).then(function () {
        btn.textContent = doc.documentElement.lang === "de" ? "Kopiert" : "Copied";
        window.setTimeout(function () { btn.textContent = originalLabel; }, 1600);
      }).catch(function () {
        btn.textContent = doc.documentElement.lang === "de" ? "Bitte Text auswählen" : "Select the text to copy";
        window.setTimeout(function () { btn.textContent = originalLabel; }, 2400);
      });
    });
  }

})();
