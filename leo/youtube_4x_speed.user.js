// ==UserScript==
// @name         YouTube 4倍速（Leo検索用）
// @namespace    http://tampermonkey.net/
// @version      1.0
// @description  YouTube動画を自動で4倍速再生にする
// @match        https://www.youtube.com/watch*
// @grant        none
// ==/UserScript==

(function() {
    'use strict';

    function setSpeed() {
        const video = document.querySelector('video');
        if (video) {
            video.playbackRate = 4;
            return true;
        }
        return false;
    }

    // 動画が読み込まれるまでリトライ
    let attempts = 0;
    const interval = setInterval(() => {
        if (setSpeed() || attempts > 30) {
            clearInterval(interval);
        }
        attempts++;
    }, 500);

    // ページ内遷移対応（SPAのため）
    const observer = new MutationObserver(() => {
        setTimeout(setSpeed, 1000);
    });
    observer.observe(document.body, { childList: true, subtree: true });
})();
