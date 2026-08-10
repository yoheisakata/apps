// まなびアプリ: 6歳向け たしざん・くく・ひらがな・タイピング学習
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

  var PRAISE = ["せいかい!", "すごい!", "やったね!", "その ちょうし!"];

  // たしざんレベル
  var MATH_LEVELS = [
    { label: "レベル1：1〜5のたしざん", aMax: 5, bMax: 4, emoji: "🍎" },
    { label: "レベル2：1〜9のたしざん", aMax: 8, bMax: 8, emoji: "🍊" },
    { label: "レベル3：10までのたしざん", aMax: 9, bMax: 9, emoji: "🍓" },
    { label: "レベル4：2けた＋1けた", aMax: 15, bMax: 9, emoji: "🐶" },
    { label: "レベル5：おおきいかず！", aMax: 20, bMax: 20, emoji: "🚗" }
  ];

  // くく（かけざん）だんごとの読み上げデータ
  var DAN_EMOJI = ["⭐", "🍎", "🌸", "🐸", "⚽", "🦋", "🌈", "🐬", "💎"];
  var KUKU = [
    [
      { a: 1, b: 1, ans: 1, yomi: "いんいちが いち" },
      { a: 1, b: 2, ans: 2, yomi: "いんにが に" },
      { a: 1, b: 3, ans: 3, yomi: "いんさんが さん" },
      { a: 1, b: 4, ans: 4, yomi: "いんしが し" },
      { a: 1, b: 5, ans: 5, yomi: "いんごが ご" },
      { a: 1, b: 6, ans: 6, yomi: "いんろくが ろく" },
      { a: 1, b: 7, ans: 7, yomi: "いんしちが しち" },
      { a: 1, b: 8, ans: 8, yomi: "いんはちが はち" },
      { a: 1, b: 9, ans: 9, yomi: "いんくが く" }
    ], [
      { a: 2, b: 1, ans: 2, yomi: "にいちが に" },
      { a: 2, b: 2, ans: 4, yomi: "ににんが し" },
      { a: 2, b: 3, ans: 6, yomi: "にさんが ろく" },
      { a: 2, b: 4, ans: 8, yomi: "にしが はち" },
      { a: 2, b: 5, ans: 10, yomi: "にご じゅう" },
      { a: 2, b: 6, ans: 12, yomi: "にろく じゅうに" },
      { a: 2, b: 7, ans: 14, yomi: "にしち じゅうし" },
      { a: 2, b: 8, ans: 16, yomi: "にはち じゅうろく" },
      { a: 2, b: 9, ans: 18, yomi: "にく じゅうはち" }
    ], [
      { a: 3, b: 1, ans: 3, yomi: "さんいちが さん" },
      { a: 3, b: 2, ans: 6, yomi: "さんにが ろく" },
      { a: 3, b: 3, ans: 9, yomi: "さざんが く" },
      { a: 3, b: 4, ans: 12, yomi: "さんし じゅうに" },
      { a: 3, b: 5, ans: 15, yomi: "さんご じゅうご" },
      { a: 3, b: 6, ans: 18, yomi: "さんろく じゅうはち" },
      { a: 3, b: 7, ans: 21, yomi: "さんしち にじゅういち" },
      { a: 3, b: 8, ans: 24, yomi: "さんぱ にじゅうし" },
      { a: 3, b: 9, ans: 27, yomi: "さんく にじゅうしち" }
    ], [
      { a: 4, b: 1, ans: 4, yomi: "しいちが し" },
      { a: 4, b: 2, ans: 8, yomi: "しにが はち" },
      { a: 4, b: 3, ans: 12, yomi: "しさん じゅうに" },
      { a: 4, b: 4, ans: 16, yomi: "しし じゅうろく" },
      { a: 4, b: 5, ans: 20, yomi: "しご にじゅう" },
      { a: 4, b: 6, ans: 24, yomi: "しろく にじゅうし" },
      { a: 4, b: 7, ans: 28, yomi: "ししち にじゅうはち" },
      { a: 4, b: 8, ans: 32, yomi: "しはち さんじゅうに" },
      { a: 4, b: 9, ans: 36, yomi: "しく さんじゅうろく" }
    ], [
      { a: 5, b: 1, ans: 5, yomi: "ごいちが ご" },
      { a: 5, b: 2, ans: 10, yomi: "ごに じゅう" },
      { a: 5, b: 3, ans: 15, yomi: "ごさん じゅうご" },
      { a: 5, b: 4, ans: 20, yomi: "ごし にじゅう" },
      { a: 5, b: 5, ans: 25, yomi: "ごご にじゅうご" },
      { a: 5, b: 6, ans: 30, yomi: "ごろく さんじゅう" },
      { a: 5, b: 7, ans: 35, yomi: "ごしち さんじゅうご" },
      { a: 5, b: 8, ans: 40, yomi: "ごはち しじゅう" },
      { a: 5, b: 9, ans: 45, yomi: "ごく しじゅうご" }
    ], [
      { a: 6, b: 1, ans: 6, yomi: "ろくいちが ろく" },
      { a: 6, b: 2, ans: 12, yomi: "ろくに じゅうに" },
      { a: 6, b: 3, ans: 18, yomi: "ろくさん じゅうはち" },
      { a: 6, b: 4, ans: 24, yomi: "ろくし にじゅうし" },
      { a: 6, b: 5, ans: 30, yomi: "ろくご さんじゅう" },
      { a: 6, b: 6, ans: 36, yomi: "ろくろく さんじゅうろく" },
      { a: 6, b: 7, ans: 42, yomi: "ろくしち しじゅうに" },
      { a: 6, b: 8, ans: 48, yomi: "ろくはち しじゅうはち" },
      { a: 6, b: 9, ans: 54, yomi: "ろっく ごじゅうし" }
    ], [
      { a: 7, b: 1, ans: 7, yomi: "しちいちが しち" },
      { a: 7, b: 2, ans: 14, yomi: "しちに じゅうし" },
      { a: 7, b: 3, ans: 21, yomi: "しちさん にじゅういち" },
      { a: 7, b: 4, ans: 28, yomi: "しちし にじゅうはち" },
      { a: 7, b: 5, ans: 35, yomi: "しちご さんじゅうご" },
      { a: 7, b: 6, ans: 42, yomi: "しちろく しじゅうに" },
      { a: 7, b: 7, ans: 49, yomi: "しちしち しじゅうく" },
      { a: 7, b: 8, ans: 56, yomi: "しちはち ごじゅうろく" },
      { a: 7, b: 9, ans: 63, yomi: "しちく ろくじゅうさん" }
    ], [
      { a: 8, b: 1, ans: 8, yomi: "はちいちが はち" },
      { a: 8, b: 2, ans: 16, yomi: "はちに じゅうろく" },
      { a: 8, b: 3, ans: 24, yomi: "はちさん にじゅうし" },
      { a: 8, b: 4, ans: 32, yomi: "はちし さんじゅうに" },
      { a: 8, b: 5, ans: 40, yomi: "はちご しじゅう" },
      { a: 8, b: 6, ans: 48, yomi: "はちろく しじゅうはち" },
      { a: 8, b: 7, ans: 56, yomi: "はちしち ごじゅうろく" },
      { a: 8, b: 8, ans: 64, yomi: "はっぱ ろくじゅうし" },
      { a: 8, b: 9, ans: 72, yomi: "はちく しちじゅうに" }
    ], [
      { a: 9, b: 1, ans: 9, yomi: "くいちが く" },
      { a: 9, b: 2, ans: 18, yomi: "くに じゅうはち" },
      { a: 9, b: 3, ans: 27, yomi: "くさん にじゅうしち" },
      { a: 9, b: 4, ans: 36, yomi: "くし さんじゅうろく" },
      { a: 9, b: 5, ans: 45, yomi: "くご しじゅうご" },
      { a: 9, b: 6, ans: 54, yomi: "くろく ごじゅうし" },
      { a: 9, b: 7, ans: 63, yomi: "くしち ろくじゅうさん" },
      { a: 9, b: 8, ans: 72, yomi: "くはち しちじゅうに" },
      { a: 9, b: 9, ans: 81, yomi: "くく はちじゅういち" }
    ]
  ];

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
    mode: null,          // "math" | "trace" | "kuku" | "typing"
    pool: null,          // なぞりがきの出題対象
    mathLevel: 0,        // たしざんレベル (0〜4)
    questionIndex: 0,
    correctFirstTry: 0,
    answeredWrong: false,
    current: null
  };

  // ---- くく状態 ----
  var kuku = { dan: 0, idx: 0 };

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
    makeMathQuestion();
  }

  function renderProgress() {
    var dots = "";
    for (var i = 0; i < QUESTIONS_PER_SESSION; i++) {
      dots += i < state.questionIndex ? "●" : "○";
    }
    document.getElementById("progress").textContent = dots;
  }

  // ---- たしざん ----
  function buildMathLevelScreen() {
    var grid = document.getElementById("level-grid");
    grid.innerHTML = "";
    MATH_LEVELS.forEach(function (lv, i) {
      var btn = document.createElement("button");
      btn.className = "level-btn";
      btn.innerHTML = "<span class=\"level-emoji\">" + lv.emoji + "</span><span class=\"level-label\">" + lv.label + "</span>";
      btn.onclick = function () {
        state.mathLevel = i;
        startSession("math");
      };
      grid.appendChild(btn);
    });
  }

  function makeMathQuestion() {
    var lv = MATH_LEVELS[state.mathLevel];
    var a = randInt(1, lv.aMax);
    var b = randInt(1, lv.bMax);
    var answer = a + b;
    var emoji = lv.emoji;

    state.current = { answer: answer };

    var qa = document.getElementById("question-area");
    qa.innerHTML = "";
    var visual = document.createElement("div");
    visual.className = "math-visual";
    if (a <= 10 && b <= 10) {
      visual.textContent = emoji.repeat(a) + "　と　" + emoji.repeat(b);
    } else {
      visual.textContent = emoji + "　と　" + emoji;
    }
    var formula = document.createElement("div");
    formula.className = "math-formula";
    formula.textContent = a + " + " + b + " = ?";
    qa.appendChild(visual);
    qa.appendChild(formula);

    // 3択: 正解 + 近い数2つ
    var choices = [answer];
    while (choices.length < 3) {
      var c = answer + randInt(-5, 5);
      if (c >= 0 && choices.indexOf(c) === -1) choices.push(c);
    }
    renderChoices(shuffle(choices), answer);
    speak(a + " たす " + b + " は なにかな?");
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
        keyEl.addEventListener("click", function () {
          if (!typing.active) return;
          onTypingKey(key);
        });
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
      btn.onclick = function () { startTrace(row.chars); };
      grid.appendChild(btn);
    });
  }

  // ---- なぞりがき ----
  var TRACE_SIZE = 320;        // 論理キャンバスサイズ
  var TRACE_FONT = "240px 'Hiragino Maru Gothic ProN', 'BIZ UDGothic', 'Yu Gothic', sans-serif";
  var TRACE_BRUSH = 20;        // なぞり判定の半径
  var TRACE_LINE_WIDTH = 26;   // なぞり線の太さ
  var TRACE_SAMPLE_STEP = 6;   // お手本の標本間隔(px)
  var TRACE_DONE_RATIO = 0.85; // この割合なぞれたら合格

  var trace = {
    active: false,
    chars: [],
    index: 0,
    doneCount: 0,
    points: [],       // お手本グリフの標本点 [{x, y, hit}]
    hitCount: 0,
    charDone: false,
    drawing: false,
    lastX: 0,
    lastY: 0,
    canvas: null,
    ctx: null
  };

  function setupTraceCanvas() {
    if (trace.canvas) return;
    var canvas = document.getElementById("trace-canvas");
    var dpr = window.devicePixelRatio || 1;
    canvas.width = TRACE_SIZE * dpr;
    canvas.height = TRACE_SIZE * dpr;
    trace.canvas = canvas;
    trace.ctx = canvas.getContext("2d");
    trace.ctx.setTransform(dpr, 0, 0, dpr, 0, 0);

    canvas.addEventListener("pointerdown", function (e) {
      if (!trace.active || trace.charDone) return;
      e.preventDefault();
      canvas.setPointerCapture(e.pointerId);
      trace.drawing = true;
      var p = tracePos(e);
      trace.lastX = p.x;
      trace.lastY = p.y;
      traceStroke(p.x, p.y, p.x, p.y);
    });
    canvas.addEventListener("pointermove", function (e) {
      if (!trace.drawing || trace.charDone) return;
      e.preventDefault();
      var p = tracePos(e);
      traceStroke(trace.lastX, trace.lastY, p.x, p.y);
      trace.lastX = p.x;
      trace.lastY = p.y;
    });
    function stop() { trace.drawing = false; }
    canvas.addEventListener("pointerup", stop);
    canvas.addEventListener("pointercancel", stop);
  }

  function tracePos(e) {
    var rect = trace.canvas.getBoundingClientRect();
    return {
      x: (e.clientX - rect.left) * (TRACE_SIZE / rect.width),
      y: (e.clientY - rect.top) * (TRACE_SIZE / rect.height)
    };
  }

  function drawTraceGlyph(ctx, ch, color) {
    ctx.fillStyle = color;
    ctx.font = TRACE_FONT;
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    ctx.fillText(ch, TRACE_SIZE / 2, TRACE_SIZE / 2 + 12);
  }

  function drawTraceBase(ch) {
    var ctx = trace.ctx;
    ctx.clearRect(0, 0, TRACE_SIZE, TRACE_SIZE);
    // ガイドの十字点線
    ctx.save();
    ctx.strokeStyle = "#e8e0d0";
    ctx.lineWidth = 2;
    ctx.setLineDash([8, 8]);
    ctx.beginPath();
    ctx.moveTo(TRACE_SIZE / 2, 0);
    ctx.lineTo(TRACE_SIZE / 2, TRACE_SIZE);
    ctx.moveTo(0, TRACE_SIZE / 2);
    ctx.lineTo(TRACE_SIZE, TRACE_SIZE / 2);
    ctx.stroke();
    ctx.restore();
    drawTraceGlyph(ctx, ch, "#d9d9d9");
  }

  // お手本グリフを別キャンバスに描き、なぞり判定用の標本点を取る
  function sampleTraceGlyph(ch) {
    var off = document.createElement("canvas");
    off.width = TRACE_SIZE;
    off.height = TRACE_SIZE;
    var ctx = off.getContext("2d");
    drawTraceGlyph(ctx, ch, "#000");
    var data = ctx.getImageData(0, 0, TRACE_SIZE, TRACE_SIZE).data;
    var points = [];
    for (var y = 0; y < TRACE_SIZE; y += TRACE_SAMPLE_STEP) {
      for (var x = 0; x < TRACE_SIZE; x += TRACE_SAMPLE_STEP) {
        if (data[(y * TRACE_SIZE + x) * 4 + 3] > 128) {
          points.push({ x: x, y: y, hit: false });
        }
      }
    }
    return points;
  }

  function traceStroke(x0, y0, x1, y1) {
    var ctx = trace.ctx;
    ctx.strokeStyle = "#ff9f1c";
    ctx.lineWidth = TRACE_LINE_WIDTH;
    ctx.lineCap = "round";
    ctx.lineJoin = "round";
    ctx.beginPath();
    ctx.moveTo(x0, y0);
    ctx.lineTo(x1, y1);
    ctx.stroke();

    // 線分に沿って標本点をカバー判定
    var dx = x1 - x0;
    var dy = y1 - y0;
    var len = Math.sqrt(dx * dx + dy * dy);
    var steps = Math.max(1, Math.ceil(len / (TRACE_BRUSH / 2)));
    for (var s = 0; s <= steps; s++) {
      var px = x0 + (dx * s) / steps;
      var py = y0 + (dy * s) / steps;
      trace.points.forEach(function (pt) {
        if (pt.hit) return;
        var ddx = pt.x - px;
        var ddy = pt.y - py;
        if (ddx * ddx + ddy * ddy <= TRACE_BRUSH * TRACE_BRUSH) {
          pt.hit = true;
          trace.hitCount++;
        }
      });
    }

    if (trace.points.length && trace.hitCount / trace.points.length >= TRACE_DONE_RATIO) {
      completeTraceChar();
    }
  }

  function renderTraceProgress() {
    var dots = "";
    for (var i = 0; i < trace.chars.length; i++) {
      dots += i < trace.index ? "●" : "○";
    }
    document.getElementById("trace-progress").textContent = dots;
  }

  function nextTraceChar() {
    trace.charDone = false;
    trace.drawing = false;
    trace.hitCount = 0;
    document.getElementById("trace-feedback").textContent = "";
    var ch = trace.chars[trace.index];
    trace.points = sampleTraceGlyph(ch);
    drawTraceBase(ch);
    renderTraceProgress();
    speak("「" + ch + "」を なぞってね");
  }

  function completeTraceChar() {
    trace.charDone = true;
    trace.drawing = false;
    trace.doneCount++;
    trace.index++;
    soundCorrect();
    // なぞった文字を緑でくっきり見せる
    drawTraceGlyph(trace.ctx, trace.chars[trace.index - 1], "rgba(42, 157, 143, 0.75)");
    var praise = pick(PRAISE);
    document.getElementById("trace-feedback").textContent = "⭕ " + praise;
    speak(praise);
    setTimeout(function () {
      if (!trace.active) return;
      if (trace.index >= trace.chars.length) {
        state.correctFirstTry = trace.doneCount;
        finishSession();
      } else {
        nextTraceChar();
      }
    }, 1400);
  }

  function traceSkip() {
    if (trace.charDone) return; // 自動で つぎへ 進む待ち
    trace.index++;
    if (trace.index >= trace.chars.length) {
      state.correctFirstTry = trace.doneCount;
      finishSession();
    } else {
      nextTraceChar();
    }
  }

  function startTrace(pool) {
    trace.active = true;
    trace.chars = pool ? pool.slice() : shuffle(ALL_CHARS).slice(0, QUESTIONS_PER_SESSION);
    trace.index = 0;
    trace.doneCount = 0;
    state.mode = "trace"; // 「もういちど」用
    state.pool = pool || null;
    setupTraceCanvas();
    show("screen-trace");
    nextTraceChar();
  }

  // ---- くく（かけざん） ----
  function buildDanScreen() {
    var grid = document.getElementById("dan-grid");
    grid.innerHTML = "";
    DAN_EMOJI.forEach(function (emoji, i) {
      var btn = document.createElement("button");
      btn.className = "row-btn";
      btn.textContent = emoji + " " + (i + 1) + "のだん";
      btn.onclick = function () { startKukuDan(i); };
      grid.appendChild(btn);
    });
  }

  function startKukuDan(i) {
    kuku.dan = i;
    kuku.idx = 0;
    state.mode = "kuku"; // 「もういちど」用
    show("screen-kuku-study");
    renderKukuEntry();
  }

  function renderKukuEntry() {
    var entry = KUKU[kuku.dan][kuku.idx];
    var emoji = DAN_EMOJI[kuku.dan];

    var dots = "";
    for (var i = 0; i < 9; i++) dots += i < kuku.idx ? "●" : "○";
    document.getElementById("kuku-progress").textContent = dots;

    var visual = document.getElementById("kuku-visual");
    visual.innerHTML = "";
    if (entry.ans <= 25) {
      for (var g = 0; g < entry.b; g++) {
        var group = document.createElement("span");
        group.className = "kuku-group";
        group.textContent = emoji.repeat(entry.a);
        visual.appendChild(group);
      }
    } else {
      visual.textContent = emoji;
    }

    document.getElementById("kuku-eq").textContent = entry.a + " × " + entry.b + " = " + entry.ans;
    document.getElementById("kuku-yomi").textContent = entry.yomi;

    document.getElementById("kuku-prev-btn").disabled = kuku.idx === 0;
    document.getElementById("kuku-next-btn").textContent = kuku.idx === 8 ? "できた! 🎉" : "つぎへ →";

    speak(entry.yomi);
  }

  function kukuPrev() {
    if (kuku.idx > 0) { kuku.idx--; renderKukuEntry(); }
  }

  function kukuNext() {
    if (kuku.idx < 8) { kuku.idx++; renderKukuEntry(); }
    else finishKukuDan();
  }

  function finishKukuDan() {
    var earned = 9;
    addStars(earned);
    document.getElementById("earned-stars").textContent = "⭐".repeat(earned) + "  " + earned + "こ ゲット!";
    show("screen-celebrate");
    speak((kuku.dan + 1) + "のだん、ぜんぶ できました! ほし " + earned + "こ ゲット!");
  }

  // ---- ナビゲーション ----
  document.body.addEventListener("click", function (e) {
    var action = e.target.closest("[data-action]");
    if (!action) return;
    switch (action.dataset.action) {
      case "math":
        buildMathLevelScreen();
        show("screen-math-levels");
        break;
      case "kuku":
        buildDanScreen();
        show("screen-kuku-dan");
        break;
      case "kuku-prev":
        kukuPrev();
        break;
      case "kuku-next":
        kukuNext();
        break;
      case "kuku-speak":
        speak(KUKU[kuku.dan][kuku.idx].yomi);
        break;
      case "hiragana":
        buildRowScreen();
        show("screen-rows");
        break;
      case "trace-speak":
        if (trace.active && !trace.charDone) speak(trace.chars[trace.index]);
        break;
      case "trace-clear":
        if (trace.active && !trace.charDone) nextTraceChar();
        break;
      case "trace-skip":
        traceSkip();
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
        } else if (state.mode === "kuku") {
          startKukuDan(kuku.dan);
        } else if (state.mode === "trace") {
          startTrace(state.pool);
        } else {
          startSession(state.mode, state.pool);
        }
        break;
      case "home":
        typing.active = false;
        trace.active = false;
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
