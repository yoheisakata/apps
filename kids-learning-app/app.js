// まなびアプリ: 6歳向け たしざん・ひらがな学習
(function () {
  "use strict";

  var QUESTIONS_PER_SESSION = 10;

  // ひらがなの行データ
  var HIRAGANA_ROWS = [
    { label: "あいうえお", chars: ["あ", "い", "う", "え", "お"] },
    { label: "かきくけこ", chars: ["か", "き", "く", "け", "こ"] },
    { label: "さしすせそ", chars: ["さ", "し", "す", "せ", "そ"] },
    { label: "たちつてと", chars: ["た", "ち", "つ", "て", "と"] },
    { label: "なにぬねの", chars: ["な", "に", "ぬ", "ね", "の"] },
    { label: "はひふへほ", chars: ["は", "ひ", "ふ", "へ", "ほ"] },
    { label: "まみむめも", chars: ["ま", "み", "む", "め", "も"] },
    { label: "やゆよ", chars: ["や", "ゆ", "よ"] },
    { label: "らりるれろ", chars: ["ら", "り", "る", "れ", "ろ"] },
    { label: "わをん", chars: ["わ", "を", "ん"] },
    { label: "ぜんぶ まぜて", chars: null } // null = 全部
  ];

  var ALL_CHARS = HIRAGANA_ROWS
    .filter(function (r) { return r.chars; })
    .reduce(function (acc, r) { return acc.concat(r.chars); }, []);

  var FRUIT = ["🍎", "🍊", "🍓", "🍇", "🍌", "🐶", "🐱", "⭐"];
  var PRAISE = ["せいかい!", "すごい!", "やったね!", "その ちょうし!"];

  // ひらがな → ローマ字 (複数の打ち方を許容)
  var ROMAJI = {
    "あ": ["a"], "い": ["i"], "う": ["u"], "え": ["e"], "お": ["o"],
    "か": ["ka"], "き": ["ki"], "く": ["ku"], "け": ["ke"], "こ": ["ko"],
    "さ": ["sa"], "し": ["shi", "si"], "す": ["su"], "せ": ["se"], "そ": ["so"],
    "た": ["ta"], "ち": ["chi", "ti"], "つ": ["tsu", "tu"], "て": ["te"], "と": ["to"],
    "な": ["na"], "に": ["ni"], "ぬ": ["nu"], "ね": ["ne"], "の": ["no"],
    "は": ["ha"], "ひ": ["hi"], "ふ": ["fu", "hu"], "へ": ["he"], "ほ": ["ho"],
    "ま": ["ma"], "み": ["mi"], "む": ["mu"], "め": ["me"], "も": ["mo"],
    "や": ["ya"], "ゆ": ["yu"], "よ": ["yo"],
    "ら": ["ra"], "り": ["ri"], "る": ["ru"], "れ": ["re"], "ろ": ["ro"],
    "わ": ["wa"], "を": ["wo"], "ん": ["nn"],
    "が": ["ga"], "ぎ": ["gi"], "ぐ": ["gu"], "げ": ["ge"], "ご": ["go"],
    "ざ": ["za"], "じ": ["ji", "zi"], "ず": ["zu"], "ぜ": ["ze"], "ぞ": ["zo"],
    "だ": ["da"], "で": ["de"], "ど": ["do"],
    "ば": ["ba"], "び": ["bi"], "ぶ": ["bu"], "べ": ["be"], "ぼ": ["bo"],
    "ぱ": ["pa"], "ぴ": ["pi"], "ぷ": ["pu"], "ぺ": ["pe"], "ぽ": ["po"]
  };

  // ことばレベル: 小さい「ゃゅょっ」を含まない かんたんな ことば
  var TYPING_WORDS = [
    { word: "ねこ", emoji: "🐱" }, { word: "いぬ", emoji: "🐶" },
    { word: "うし", emoji: "🐮" }, { word: "とり", emoji: "🐦" },
    { word: "さかな", emoji: "🐟" }, { word: "うみ", emoji: "🌊" },
    { word: "そら", emoji: "☁️" }, { word: "やま", emoji: "⛰️" },
    { word: "ほし", emoji: "⭐" }, { word: "つき", emoji: "🌙" },
    { word: "はな", emoji: "🌸" }, { word: "みかん", emoji: "🍊" },
    { word: "りんご", emoji: "🍎" }, { word: "すいか", emoji: "🍉" },
    { word: "くつ", emoji: "👟" }, { word: "かさ", emoji: "☂️" },
    { word: "ふね", emoji: "⛵" }, { word: "にじ", emoji: "🌈" },
    { word: "ゆき", emoji: "⛄" }, { word: "あめ", emoji: "☔" },
    { word: "たまご", emoji: "🥚" }, { word: "ぱんだ", emoji: "🐼" },
    { word: "くるま", emoji: "🚗" }, { word: "かえる", emoji: "🐸" }
  ];

  var KEYBOARD_ROWS = ["qwertyuiop", "asdfghjkl", "zxcvbnm"];

  // ---- 状態 ----
  var state = {
    mode: null,          // "math" | "hiragana"
    pool: null,          // ひらがな出題対象
    questionIndex: 0,
    correctFirstTry: 0,
    answeredWrong: false,
    current: null
  };

  // ---- 保存された星 ----
  function getStars() {
    return parseInt(localStorage.getItem("manabi-stars") || "0", 10);
  }
  function addStars(n) {
    localStorage.setItem("manabi-stars", String(getStars() + n));
  }
  function renderStars() {
    document.getElementById("total-stars").textContent = "⭐ " + getStars();
  }

  // ---- 画面切り替え ----
  function show(id) {
    document.querySelectorAll(".screen").forEach(function (s) {
      s.classList.remove("active");
    });
    document.getElementById(id).classList.add("active");
  }

  // ---- 音声読み上げ ----
  function speak(text) {
    if (!("speechSynthesis" in window)) return;
    speechSynthesis.cancel();
    var u = new SpeechSynthesisUtterance(text);
    u.lang = "ja-JP";
    u.rate = 0.85;
    speechSynthesis.speak(u);
  }

  // ---- 効果音 ----
  var audioCtx = null;
  function beep(freqs) {
    try {
      if (!audioCtx) audioCtx = new (window.AudioContext || window.webkitAudioContext)();
      freqs.forEach(function (f, i) {
        var osc = audioCtx.createOscillator();
        var gain = audioCtx.createGain();
        osc.type = "sine";
        osc.frequency.value = f;
        gain.gain.setValueAtTime(0.15, audioCtx.currentTime + i * 0.12);
        gain.gain.exponentialRampToValueAtTime(0.001, audioCtx.currentTime + i * 0.12 + 0.25);
        osc.connect(gain).connect(audioCtx.destination);
        osc.start(audioCtx.currentTime + i * 0.12);
        osc.stop(audioCtx.currentTime + i * 0.12 + 0.3);
      });
    } catch (e) { /* 音が出なくても続行 */ }
  }
  function soundCorrect() { beep([523, 659, 784]); }
  function soundWrong() { beep([220]); }

  // ---- ユーティリティ ----
  function randInt(min, max) {
    return Math.floor(Math.random() * (max - min + 1)) + min;
  }
  function shuffle(arr) {
    var a = arr.slice();
    for (var i = a.length - 1; i > 0; i--) {
      var j = Math.floor(Math.random() * (i + 1));
      var t = a[i]; a[i] = a[j]; a[j] = t;
    }
    return a;
  }
  function pick(arr) { return arr[Math.floor(Math.random() * arr.length)]; }

  // ---- クイズ進行 ----
  function startSession(mode, pool) {
    state.mode = mode;
    state.pool = pool || null;
    state.questionIndex = 0;
    state.correctFirstTry = 0;
    show("screen-quiz");
    nextQuestion();
  }

  function nextQuestion() {
    state.answeredWrong = false;
    document.getElementById("feedback").textContent = "";
    renderProgress();
    if (state.mode === "math") {
      makeMathQuestion();
    } else {
      makeHiraganaQuestion();
    }
  }

  function renderProgress() {
    var dots = "";
    for (var i = 0; i < QUESTIONS_PER_SESSION; i++) {
      dots += i < state.questionIndex ? "●" : "○";
    }
    document.getElementById("progress").textContent = dots;
  }

  // ---- たしざん ----
  function makeMathQuestion() {
    var a = randInt(1, 5);
    var b = randInt(1, Math.min(5, 10 - a));
    var answer = a + b;
    var emoji = pick(FRUIT);

    state.current = { answer: answer };

    var qa = document.getElementById("question-area");
    qa.innerHTML = "";
    var visual = document.createElement("div");
    visual.className = "math-visual";
    visual.textContent = emoji.repeat(a) + "　と　" + emoji.repeat(b);
    var formula = document.createElement("div");
    formula.className = "math-formula";
    formula.textContent = a + " + " + b + " = ?";
    qa.appendChild(visual);
    qa.appendChild(formula);

    document.getElementById("listen-btn").hidden = true;

    // 3択: 正解 + 近い数2つ
    var choices = [answer];
    while (choices.length < 3) {
      var c = answer + randInt(-3, 3);
      if (c >= 1 && c <= 10 && choices.indexOf(c) === -1) choices.push(c);
    }
    renderChoices(shuffle(choices), answer);
    speak(a + " たす " + b + " は なにかな?");
  }

  // ---- ひらがな ----
  function makeHiraganaQuestion() {
    var pool = state.pool || ALL_CHARS;
    var answer = pick(pool);
    state.current = { answer: answer };

    var qa = document.getElementById("question-area");
    qa.innerHTML = "";
    var prompt = document.createElement("div");
    prompt.className = "hiragana-prompt";
    prompt.textContent = "きこえた もじ を えらんでね";
    qa.appendChild(prompt);

    var listenBtn = document.getElementById("listen-btn");
    listenBtn.hidden = false;
    listenBtn.onclick = function () { speak(answer); };

    // 4択: 正解 + まぎらわしい文字
    var distractors = shuffle(ALL_CHARS.filter(function (c) { return c !== answer; })).slice(0, 3);
    renderChoices(shuffle([answer].concat(distractors)), answer);
    speak("「" + answer + "」は どれかな?");
  }

  // ---- 選択肢 ----
  function renderChoices(choices, answer) {
    var box = document.getElementById("choices");
    box.innerHTML = "";
    choices.forEach(function (c) {
      var btn = document.createElement("button");
      btn.className = "choice-btn";
      btn.textContent = c;
      btn.onclick = function () { onAnswer(btn, c, answer); };
      box.appendChild(btn);
    });
  }

  function onAnswer(btn, chosen, answer) {
    if (String(chosen) === String(answer)) {
      btn.classList.add("correct");
      soundCorrect();
      var praise = pick(PRAISE);
      document.getElementById("feedback").textContent = "⭕ " + praise;
      speak(praise);
      if (!state.answeredWrong) state.correctFirstTry++;
      // ボタンを無効化して次へ
      document.querySelectorAll(".choice-btn").forEach(function (b) { b.disabled = true; });
      state.questionIndex++;
      setTimeout(function () {
        if (state.questionIndex >= QUESTIONS_PER_SESSION) {
          finishSession();
        } else {
          nextQuestion();
        }
      }, 1400);
    } else {
      state.answeredWrong = true;
      btn.classList.add("wrong");
      btn.disabled = true;
      soundWrong();
      document.getElementById("feedback").textContent = "もういちど!";
      speak("おしい! もういちど");
      setTimeout(function () { btn.classList.remove("wrong"); }, 500);
    }
  }

  function finishSession() {
    var earned = state.correctFirstTry;
    addStars(earned);
    var starsEl = document.getElementById("earned-stars");
    starsEl.textContent = "⭐".repeat(Math.max(earned, 1)) + "  " + earned + "こ ゲット!";
    show("screen-celebrate");
    speak("よくできました! ほし " + earned + "こ ゲット!");
  }

  // ---- タイピング ----
  var typing = {
    active: false,
    level: null,       // "chars" | "words"
    questionIndex: 0,
    perfectCount: 0,   // ミスなしで打てた問題数
    madeMistake: false,
    chars: [],         // 出題のひらがな配列
    emoji: "",
    charIndex: 0,
    buffer: ""
  };

  function buildKeyboard() {
    var kb = document.getElementById("keyboard");
    kb.innerHTML = "";
    KEYBOARD_ROWS.forEach(function (row) {
      var rowEl = document.createElement("div");
      rowEl.className = "kb-row";
      row.split("").forEach(function (key) {
        var keyEl = document.createElement("div");
        keyEl.className = "kb-key";
        keyEl.dataset.key = key;
        keyEl.textContent = key;
        rowEl.appendChild(keyEl);
      });
      kb.appendChild(rowEl);
    });
  }

  function startTyping(level) {
    typing.active = true;
    typing.level = level;
    typing.questionIndex = 0;
    typing.perfectCount = 0;
    state.mode = "typing"; // 「もういちど」用
    buildKeyboard();
    show("screen-typing");
    nextTypingQuestion();
  }

  function nextTypingQuestion() {
    typing.madeMistake = false;
    typing.charIndex = 0;
    typing.buffer = "";
    document.getElementById("typing-feedback").textContent = "";

    if (typing.level === "chars") {
      typing.chars = [pick(Object.keys(ROMAJI))];
      typing.emoji = "";
    } else {
      var w = pick(TYPING_WORDS);
      typing.chars = w.word.split("");
      typing.emoji = w.emoji;
    }

    var dots = "";
    for (var i = 0; i < QUESTIONS_PER_SESSION; i++) {
      dots += i < typing.questionIndex ? "●" : "○";
    }
    document.getElementById("typing-progress").textContent = dots;
    document.getElementById("typing-emoji").textContent = typing.emoji;

    renderTypingState();
    speak(typing.chars.join(""));
  }

  // 現在の文字の打ち方候補のうち、バッファと一致しているもの
  function matchingVariants() {
    var variants = ROMAJI[typing.chars[typing.charIndex]] || [];
    return variants.filter(function (v) {
      return v.indexOf(typing.buffer) === 0;
    });
  }

  function renderTypingState() {
    // ひらがな表示: 打ち終わった文字は緑、いまの文字はオレンジ下線
    var wordEl = document.getElementById("typing-word");
    wordEl.innerHTML = "";
    typing.chars.forEach(function (c, i) {
      var span = document.createElement("span");
      span.textContent = c;
      if (i < typing.charIndex) span.className = "done";
      else if (i === typing.charIndex) span.className = "now";
      wordEl.appendChild(span);
    });

    // ローマ字ガイド: いまの文字の打ち方 (先頭候補) と入力済み部分
    var romajiEl = document.getElementById("typing-romaji");
    romajiEl.innerHTML = "";
    var candidates = matchingVariants();
    var guide = candidates.length ? candidates[0] : "";
    var typedSpan = document.createElement("span");
    typedSpan.className = "typed";
    typedSpan.textContent = typing.buffer;
    romajiEl.appendChild(typedSpan);
    romajiEl.appendChild(document.createTextNode(guide.slice(typing.buffer.length)));

    // つぎに押すキーを光らせる
    var nextKey = guide.charAt(typing.buffer.length);
    document.querySelectorAll(".kb-key").forEach(function (el) {
      el.classList.remove("next");
      if (el.dataset.key === nextKey) el.classList.add("next");
    });
  }

  function flashKey(key, ok) {
    var el = document.querySelector('.kb-key[data-key="' + key + '"]');
    if (!el) return;
    var cls = ok ? "pressed-ok" : "pressed-ng";
    el.classList.add(cls);
    setTimeout(function () { el.classList.remove(cls); }, 250);
  }

  function onTypingKey(key) {
    var attempt = typing.buffer + key;
    var variants = ROMAJI[typing.chars[typing.charIndex]] || [];
    var stillMatching = variants.filter(function (v) {
      return v.indexOf(attempt) === 0;
    });

    if (stillMatching.length === 0) {
      // まちがい: バッファはそのまま、キーを赤くする
      typing.madeMistake = true;
      flashKey(key, false);
      soundWrong();
      return;
    }

    typing.buffer = attempt;
    flashKey(key, true);

    // どれかの打ち方が完成したら次の文字へ
    var completed = stillMatching.some(function (v) { return v === attempt; });
    if (completed) {
      typing.buffer = "";
      typing.charIndex++;
      if (typing.charIndex >= typing.chars.length) {
        finishTypingQuestion();
        return;
      }
    }
    renderTypingState();
  }

  function finishTypingQuestion() {
    soundCorrect();
    if (!typing.madeMistake) typing.perfectCount++;
    var praise = pick(PRAISE);
    document.getElementById("typing-feedback").textContent = "⭕ " + praise;
    speak(praise);
    // 全文字を緑で見せる
    typing.charIndex = typing.chars.length;
    renderTypingState();
    document.getElementById("typing-romaji").textContent = "";

    typing.questionIndex++;
    setTimeout(function () {
      if (typing.questionIndex >= QUESTIONS_PER_SESSION) {
        typing.active = false;
        state.correctFirstTry = typing.perfectCount;
        finishSession();
      } else {
        nextTypingQuestion();
      }
    }, 1400);
  }

  document.addEventListener("keydown", function (e) {
    if (!typing.active) return;
    if (!document.getElementById("screen-typing").classList.contains("active")) return;
    var key = e.key.toLowerCase();
    if (!/^[a-z]$/.test(key)) return;
    e.preventDefault();
    onTypingKey(key);
  });

  // ---- ひらがな行えらび ----
  function buildRowScreen() {
    var grid = document.getElementById("row-grid");
    grid.innerHTML = "";
    HIRAGANA_ROWS.forEach(function (row) {
      var btn = document.createElement("button");
      btn.className = "row-btn";
      btn.textContent = row.label;
      btn.onclick = function () { startSession("hiragana", row.chars); };
      grid.appendChild(btn);
    });
  }

  // ---- ナビゲーション ----
  document.body.addEventListener("click", function (e) {
    var action = e.target.closest("[data-action]");
    if (!action) return;
    switch (action.dataset.action) {
      case "math":
        startSession("math");
        break;
      case "hiragana":
        buildRowScreen();
        show("screen-rows");
        break;
      case "typing":
        show("screen-typing-levels");
        break;
      case "typing-chars":
        startTyping("chars");
        break;
      case "typing-words":
        startTyping("words");
        break;
      case "again":
        if (state.mode === "typing") {
          startTyping(typing.level);
        } else {
          startSession(state.mode, state.pool);
        }
        break;
      case "home":
        typing.active = false;
        speechSynthesis.cancel();
        renderStars();
        show("screen-home");
        break;
    }
  });

  // ---- Service Worker 登録 ----
  if ("serviceWorker" in navigator) {
    navigator.serviceWorker.register("sw.js").catch(function () { /* ローカルfile://等では無視 */ });
  }

  renderStars();
})();
