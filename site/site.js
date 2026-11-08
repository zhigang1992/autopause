(function () {
  var GRACE = 1500;
  var state = "idle";
  var mode = "pause";
  var timer = 0;

  var mic = document.getElementById("mic");
  var barMic = document.getElementById("bar-mic");
  var barStatus = document.getElementById("bar-status");
  var lcd1 = document.getElementById("lcd-1");
  var lcd2 = document.getElementById("lcd-2");
  var live = document.getElementById("live");
  var clock = document.getElementById("clock");

  var checked = document.querySelector('input[name="mode"]:checked');
  if (checked) mode = checked.value;

  function key() {
    if (state === "idle") return "idle";
    if (state === "grace") return "grace";
    return state + ":" + mode;
  }

  var copy = {
    idle: ["Listening", "music is up", "Listening. Music is up."],
    grace: ["Ducking: this page", "holding for 1.5s", "Ducking, this page. Holding the quiet for one and a half seconds."],
    "active:pause": ["Ducking: this page", "song is paused", "Ducking, this page. The song is paused."],
    "active:mute": ["Ducking: this page", "volume is down", "Ducking, this page. Volume is down."]
  };

  function render() {
    document.body.dataset.state = state;
    document.body.dataset.mode = mode;
    var line = copy[key()];
    lcd1.textContent = line[0];
    lcd2.textContent = line[1];
    live.textContent = line[2];
    barStatus.textContent = state === "idle" ? "Listening" : "Ducking: this page";
    var hot = state === "active";
    mic.setAttribute("aria-pressed", hot ? "true" : "false");
    barMic.setAttribute("aria-pressed", hot ? "true" : "false");
  }

  function micOn() {
    window.clearTimeout(timer);
    state = "active";
    render();
  }

  function micOff() {
    if (state !== "active") return;
    state = "grace";
    render();
    timer = window.setTimeout(function () {
      state = "idle";
      render();
    }, GRACE);
  }

  function toggle() {
    if (state === "active") micOff();
    else micOn();
  }

  mic.addEventListener("click", toggle);
  barMic.addEventListener("click", toggle);

  document.querySelectorAll('input[name="mode"]').forEach(function (el) {
    el.addEventListener("change", function () {
      if (el.checked) {
        mode = el.value;
        render();
      }
    });
  });

  document.addEventListener("keydown", function (event) {
    if (event.key !== "m" && event.key !== "M") return;
    if (event.metaKey || event.ctrlKey || event.altKey) return;
    var tag = event.target && event.target.tagName;
    if (tag === "INPUT" || tag === "TEXTAREA") return;
    event.preventDefault();
    toggle();
  });

  function tick() {
    var now = new Date();
    clock.textContent = now.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
    clock.dateTime = now.toISOString();
  }

  tick();
  window.setInterval(tick, 10000);
  render();
})();
