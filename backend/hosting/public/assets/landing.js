/*
 * 招待リンクのランディングページ（/r/{招待コード}。02 の §2.4・05 の §7）の処理。
 * アプリが入っていない端末で招待リンクを開いたときに表示する。URL のパスから招待コードを取り出し、
 * 正しいコードのときだけ大きく表示する（ディファードディープリンクは MVP の対象外なので、アプリで入力してもらう）。
 *
 * 外部の JS・CDN は使わない。コードは検証してから textContent で入れる（HTML として解釈させない）。
 * 規則はアプリの InviteCode（Swift）・Functions の inviteCode.ts と同じで、backend/hosting/test/landing.test.ts で
 * inviteCode.ts の parseInviteCode と同じ結果になることを確かめる。
 * Jest からも読めるよう、関数は globalThis.DokogachaLanding に置き、document があるときだけ画面に反映する。
 */
(function (root) {
  "use strict";

  /** 招待リンクのパスの前置き（functions/src/domain/constants.ts の INVITE_LINK_PATH_PREFIX と同じ） */
  var INVITE_LINK_PATH_PREFIX = "/r/";
  /** 使う文字（inviteCode.ts の INVITE_CODE_ALPHABET と同じ。紛らわしい 0 O 1 I を除く） */
  var INVITE_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  /** コードの文字数 */
  var INVITE_CODE_LENGTH = 6;
  /** 表示でハイフンを入れる位置 */
  var INVITE_CODE_GROUP_LENGTH = 3;
  /**
   * 入力から取り除く空白と区切りの文字（inviteCode.ts の INVITE_CODE_IGNORED_WHITESPACES・INVITE_CODE_IGNORED_SEPARATORS と同じ）。
   * JavaScript の \s に U+0085 を足すと、空白の一覧と同じになる（文字はすべて \u のエスケープで書く）
   */
  var IGNORED_CHARACTERS = /[\s\u0085\u2010-\u2015\u2212\u30FC\u002D]/gu;
  /** App Store のアプリのページ（仮の値。App Store Connect でアプリを登録したら、アプリの ID に差し替える） */
  var APP_STORE_URL = "https://apps.apple.com/jp/app/id0000000000";

  /**
   * 入力の文字列を招待コードの形に正規化する（NFKC で半角にし、空白と区切りを取り除き、大文字にする）。
   * @param {string} input
   * @returns {string}
   */
  function normalizeInviteCode(input) {
    return input.normalize("NFKC").replace(IGNORED_CHARACTERS, "").toUpperCase();
  }

  /**
   * 正規化済みの文字列が招待コードとして正しいか（6 文字で、すべて使える文字）。
   * @param {string} normalized
   * @returns {boolean}
   */
  function isValidInviteCode(normalized) {
    var list = Array.from(normalized);
    return (
      list.length === INVITE_CODE_LENGTH &&
      list.every(function (character) {
        return INVITE_CODE_ALPHABET.indexOf(character) >= 0;
      })
    );
  }

  /**
   * URL のパス（location.pathname）から招待コードを取り出す。アプリの InviteLink.inviteCode(from:) と同じ規則。
   * /r/ で始まり、その後ろが 1 つの区切りだけ（末尾のスラッシュは 1 つまで）。パーセントエンコードは戻してから読む。
   * @param {string} pathname
   * @returns {string | null} ハイフンなしの 6 文字。招待リンクでない・コードが正しくなければ null
   */
  function inviteCodeFromPath(pathname) {
    if (pathname.indexOf(INVITE_LINK_PATH_PREFIX) !== 0) {
      return null;
    }
    var rest = pathname.slice(INVITE_LINK_PATH_PREFIX.length);
    if (rest.slice(-1) === "/") {
      rest = rest.slice(0, -1);
    }
    var decoded;
    try {
      decoded = decodeURIComponent(rest);
    } catch {
      return null;
    }
    if (decoded === "" || decoded.indexOf("/") >= 0) {
      return null;
    }
    var normalized = normalizeInviteCode(decoded);
    return isValidInviteCode(normalized) ? normalized : null;
  }

  /**
   * 表示の形にする（先頭から 3 文字目の後ろにハイフン。DK7-29Q）。
   * @param {string} code ハイフンなしの 6 文字
   * @returns {string}
   */
  function formatInviteCode(code) {
    return code.slice(0, INVITE_CODE_GROUP_LENGTH) + "-" + code.slice(INVITE_CODE_GROUP_LENGTH);
  }

  /**
   * 画面に反映する。正しい招待コードなら招待コードのカードに入れて出し、正しくなければカードを隠す。
   * App Store のボタンのリンク先も入れる。
   * @param {Document} doc
   * @param {string} pathname
   * @returns {string | null} 表示した招待コード（ハイフンなし）
   */
  function render(doc, pathname) {
    var storeLink = doc.getElementById("app-store-link");
    if (storeLink) {
      storeLink.setAttribute("href", APP_STORE_URL);
    }
    var card = doc.getElementById("invite-code-card");
    var codeText = doc.getElementById("invite-code");
    var code = inviteCodeFromPath(pathname);
    if (!card || !codeText) {
      return code;
    }
    if (code === null) {
      card.hidden = true;
      codeText.textContent = "";
      return null;
    }
    codeText.textContent = formatInviteCode(code);
    card.hidden = false;
    return code;
  }

  root.DokogachaLanding = {
    APP_STORE_URL: APP_STORE_URL,
    normalizeInviteCode: normalizeInviteCode,
    isValidInviteCode: isValidInviteCode,
    inviteCodeFromPath: inviteCodeFromPath,
    formatInviteCode: formatInviteCode,
    render: render,
  };

  if (typeof document !== "undefined" && typeof location !== "undefined") {
    render(document, location.pathname);
  }
})(globalThis);
