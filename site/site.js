(function () {
  var STR = {
    en: {
      title: "Autopause — the song sits down",
      skip: "Skip to the words",
      kicker: "macOS menu bar",
      h1a: "the mic is on.",
      h1b: "the song sits down.",
      lede: "A menu-bar app for Mac. While you dictate — 豆包输入法, or any microphone — it pauses or mutes the music, then brings it back. It never records you.",
      dl: "Download for Mac",
      dlsmall: "1.1.1 · notarized zip · 1.5 MB",
      more: "Read more on GitHub",
      moreHref: "https://github.com/zhigang1992/autopause#what-it-does",
      fine: "Unzip it and move Autopause into Applications. macOS 14 or later.",
      hint: "Press the mic. The real app notices a microphone by itself.",
      foot: "The longer explanation is on GitHub.",
      pause: "Pause",
      mute: "Mute",
      mic: "Pretend the microphone is in use",
      switch: "How the music ducks",
      lostA: "this page",
      lostB: "sat down.",
      lostLede: "Nothing lives at this address.",
      lostBack: "Back home",
      lostSmall: "autopause.reily.app"
    },
    zh: {
      title: "Autopause — 听写的时候，音乐先安静",
      skip: "跳到正文",
      kicker: "macOS 菜单栏",
      h1a: "听写的时候，",
      h1b: "音乐先安静。",
      lede: "菜单栏里的小应用。用豆包输入法或其他方式说话时，正在放的音乐会暂停或静音，说完再回来。不录音。",
      dl: "下载 Mac 版",
      dlsmall: "1.1.1 · 已公证 · 1.5 MB",
      more: "在 GitHub 上看说明",
      moreHref: "https://github.com/zhigang1992/autopause#这是做什么的",
      fine: "解压后放进「应用程序」。需要 macOS 14 或更新。",
      hint: "按一下麦克风试试。真正听写时不用按，它自己能发现。",
      foot: "更完整的说明在 GitHub。",
      pause: "暂停",
      mute: "静音",
      mic: "假装麦克风正在使用",
      switch: "音乐怎么安静",
      lostA: "这一页",
      lostB: "先坐下了。",
      lostLede: "这里什么都没有。",
      lostBack: "回到首页",
      lostSmall: "autopause.reily.app"
    }
  };

  var LCD = {
    en: {
      idle: ["Listening", "music is up", "Listening. Music is up."],
      grace: ["Ducking: this page", "holding for 1.5s", "Ducking, this page. Holding the quiet for one and a half seconds."],
      "active:pause": ["Ducking: this page", "song is paused", "Ducking, this page. The song is paused."],
      "active:mute": ["Ducking: this page", "volume is down", "Ducking, this page. Volume is down."]
    },
    zh: {
      idle: ["在听", "音乐开着", "在听。音乐开着。"],
      grace: ["正在安静：这个页面", "再等 1.5 秒", "正在安静，这个页面。再等一秒半。"],
      "active:pause": ["正在安静：这个页面", "歌暂停了", "正在安静，这个页面。歌暂停了。"],
      "active:mute": ["正在安静：这个页面", "音量降下了", "正在安静，这个页面。音量降下了。"]
    }
  };

  var stored = null;
  try { stored = localStorage.getItem("autopause-lang"); } catch (e) {}
  var requested = new URLSearchParams(location.search).get("lang");
  if (requested === "zh" || requested === "en") stored = requested;
  var lang = stored === "zh" || stored === "en"
    ? stored
    : (navigator.language || "").toLowerCase().indexOf("zh") === 0 ? "zh" : "en";

  function t(key) {
    return (STR[lang] && STR[lang][key]) || STR.en[key] || "";
  }

  function apply(next) {
    lang = next === "zh" ? "zh" : "en";
    try { localStorage.setItem("autopause-lang", lang); } catch (e) {}
    document.documentElement.lang = lang === "zh" ? "zh-Hans" : "en";
    var lost = lang === "zh" ? t("lostA") + t("lostB") : t("lostA") + " " + t("lostB");
    document.title = document.getElementById("content") ? t("title") : lost + " — Autopause";
    var desc = document.querySelector('meta[name="description"]');
    if (desc) desc.setAttribute("content", t("lede"));
    document.querySelectorAll("[data-i18n]").forEach(function (el) {
      el.textContent = t(el.getAttribute("data-i18n"));
    });
    document.querySelectorAll("[data-i18n-aria]").forEach(function (el) {
      el.setAttribute("aria-label", t(el.getAttribute("data-i18n-aria")));
    });
    document.querySelectorAll("[data-set-lang]").forEach(function (el) {
      el.setAttribute("aria-pressed", el.getAttribute("data-set-lang") === lang ? "true" : "false");
    });
    document.querySelectorAll("[data-i18n-href]").forEach(function (el) {
      el.href = t(el.getAttribute("data-i18n-href"));
    });
    if (lcd1) render();
  }

  document.querySelectorAll("[data-set-lang]").forEach(function (el) {
    el.addEventListener("click", function () {
      apply(el.getAttribute("data-set-lang"));
    });
  });

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

  function lineKey() {
    if (state === "idle") return "idle";
    if (state === "grace") return "grace";
    return state + ":" + mode;
  }

  function render() {
    document.body.dataset.state = state;
    document.body.dataset.mode = mode;
    var line = LCD[lang][lineKey()];
    if (lcd1) lcd1.textContent = line[0];
    if (lcd2) lcd2.textContent = line[1];
    if (live) live.textContent = line[2];
    if (barStatus) barStatus.textContent = state === "idle" ? line[0] : line[0];
    var hot = state === "active";
    if (mic) mic.setAttribute("aria-pressed", hot ? "true" : "false");
    if (barMic) barMic.setAttribute("aria-pressed", hot ? "true" : "false");
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

  if (mic && barMic) {
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
      if (tag === "INPUT" || tag === "TEXTAREA" || tag === "BUTTON") return;
      event.preventDefault();
      toggle();
    });
    render();
  }

  if (clock) {
    var tick = function () {
      var now = new Date();
      clock.textContent = now.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
      clock.dateTime = now.toISOString();
    };
    tick();
    window.setInterval(tick, 10000);
  }

  apply(lang);
})();
