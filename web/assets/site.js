/* Sonoglitch web: progressive enhancement. The page is whole and readable without this file.
   1. Blocks marked data-reveal come in when scrolled to. Only the ones below the fold at load are hidden, so nothing
      flickers. data-reveal="stagger" brings its children in 70 ms apart.
   2. Loops marked data-loop (the three small demos in Features and the meters under the cover) wait until they are
      on screen and stop when they leave it, so nothing runs out of sight.
   No storage and no network. With "reduce motion" it does nothing and the CSS shows the still version. */
(function () {
  "use strict";
  if (!("IntersectionObserver" in window)) return;
  if (!window.matchMedia || window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;

  var each = function (list, fn) { Array.prototype.forEach.call(list, fn); };

  var pending = Array.prototype.filter.call(document.querySelectorAll("[data-reveal]"), function (el) {
    return el.getBoundingClientRect().top > window.innerHeight;
  });
  if (pending.length) {
    var revealer = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (!entry.isIntersecting) return;
        entry.target.classList.add("in");
        revealer.unobserve(entry.target);
      });
    }, { rootMargin: "0px 0px -12% 0px" });
    pending.forEach(function (el) {
      el.classList.add("reveal");
      if (el.getAttribute("data-reveal") === "stagger") el.classList.add("stagger");
      revealer.observe(el);
    });
  }

  var loops = document.querySelectorAll("[data-loop]");
  if (loops.length) {
    var pauser = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        entry.target.classList.toggle("is-paused", !entry.isIntersecting);
      });
    }, { rootMargin: "80px 0px" });
    each(loops, function (el) {
      /* Start paused: a loop that is off screen has not moved, so it begins at its first frame when it is reached. */
      el.classList.add("is-paused");
      pauser.observe(el);
    });
  }
})();
