const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const {JSDOM} = require('jsdom');
const source = fs.readFileSync(require('node:path').join(__dirname, '../AntigravityRemote/Utils/UserAgentHelper.swift'), 'utf8').split('enum GoogleAccountBridge')[1].split('#"""')[1].split('"""#')[0];
const wait = () => new Promise(resolve => setTimeout(resolve, 180));
function page(html, url = 'https://antigravity.google.com/') {
  const dom = new JSDOM(html, {url, runScripts: 'outside-only'});
  const messages = [];
  dom.window.HTMLElement.prototype.getClientRects = function() { return this.hidden ? [] : [1]; };
  dom.window.webkit = {messageHandlers: {googleAccount: {postMessage: email => messages.push(email)}}};
  dom.window.eval(source);
  return {dom, messages};
}
test('remembers delayed profile and subsequent SPA account switches', async () => {
  const {dom, messages} = page('<title>Antigravity</title>');
  try {
    assert.deepEqual(messages, []);
    dom.window.document.body.innerHTML = '<button aria-label="Google Account: Alice (alice@example.com)"></button>';
    await wait();
    dom.window.document.querySelector('button').setAttribute('aria-label', 'Google 账号：Bob (bob@example.com)');
    await wait();
    assert.deepEqual(messages, ['alice@example.com', 'bob@example.com']);
  } finally { dom.window.close(); }
});
test('ignores chooser entries, unrelated emails, titles and hidden profiles', () => {
  const {dom, messages} = page('<title>fake@example.com</title><div data-email="default@example.com"></div><button aria-label="Contact other@example.com"></button><div role="dialog"><button aria-label="Google Account: default@example.com"></button></div><button hidden aria-label="Google Account: hidden@example.com"></button>');
  assert.deepEqual(messages, []);
  dom.window.close();
});
test('login chooser cannot overwrite the saved account', () => {
  for (const url of ['https://accounts.google.com/', 'https://google.com.evil.test/']) {
    const {dom, messages} = page('<button aria-label="Google Account: default@example.com"></button>', url);
    assert.deepEqual(messages, []);
    dom.window.close();
  }
});

test('avatar interaction dismisses notice without blocking Google menu', () => {
  const {dom, messages} = page('<a aria-label="Google Account: Bob (bob@example.com)"><img id="avatar"></a><button id="unrelated">Other</button>');
  try {
    const before = messages.length;
    dom.window.document.querySelector('#unrelated').click();
    assert.equal(messages.length, before);
    let googleOpened = false;
    const avatar = dom.window.document.querySelector('#avatar');
    avatar.parentElement.addEventListener('click', () => { googleOpened = true; });
    avatar.dispatchEvent(new dom.window.Event('pointerdown', {bubbles:true}));
    avatar.click();
    assert.equal(messages.at(-1).event, 'accountChooserOpened');
    assert.equal(googleOpened, true);
  } finally { dom.window.close(); }
});

test('Google iframe selection captures numeric authuser before popup navigation, including default', () => {
  for (const index of ['2', '0']) {
    const {dom, messages} = page(`<a href="https://antigravity.google.com/?authuser=${index}&pageId=none" target="_blank"><span>Account</span></a>`, 'https://ogs.google.com/u/0/widget/account');
    try {
      let navigated = false;
      dom.window.document.querySelector('a').addEventListener('click', () => { navigated = true; });
      const event = new dom.window.MouseEvent('click', {bubbles:true, cancelable:true});
      dom.window.document.querySelector('span').dispatchEvent(event);
      assert.deepEqual(JSON.parse(JSON.stringify(messages)), [{event:'accountSelected', index}]);
      assert.equal(event.defaultPrevented, true);
      assert.equal(navigated, false);
    } finally { dom.window.close(); }
  }
});

test('normal instance links and invalid account links are not intercepted', () => {
  const {dom, messages} = page('<a></a>');
  try {
    const anchor = dom.window.document.querySelector('a');
    for (const href of ['https://antigravity.google.com/u/2/r/another', 'https://antigravity.google.com/?authuser=person@example.com', 'https://antigravity.google.com.evil.test/?authuser=2', 'https://accounts.google.com/?authuser=2']) {
      anchor.href = href;
      const event = new dom.window.MouseEvent('click', {bubbles:true, cancelable:true});
      anchor.addEventListener('click', e => e.preventDefault(), {once:true}); // Avoid jsdom navigation.
      anchor.dispatchEvent(event);
      assert.equal(messages.length, 0);
    }
  } finally { dom.window.close(); }
});

test('signed-out welcome page reports once, signed-in header does not', async () => {
  const signIn = '<div id="gb"><a aria-label="Sign in" href="https://accounts.google.com/ServiceLogin?passive=1209600&continue=https://antigravity.google.com/">Sign in</a></div>';
  const {dom, messages} = page(signIn);
  try {
    dom.window.document.body.appendChild(dom.window.document.createElement('div'));
    await wait();
    assert.deepEqual(JSON.parse(JSON.stringify(messages)), [{event: 'signedOut'}]);
    dom.window.document.querySelector('#gb').innerHTML = '<a aria-label="Google Account: Alice (alice@example.com)" href="https://accounts.google.com/SignOutOptions"></a>';
    await wait();
    assert.equal(messages.at(-1), 'alice@example.com');
  } finally { dom.window.close(); }
  for (const html of [
    '<div id="gb"><a aria-label="Google Account: Bob (bob@example.com)"></a></div>',
    '<a href="https://accounts.google.com/ServiceLogin?continue=x">Sign in elsewhere</a>',
    '<div id="gb"><a hidden href="https://accounts.google.com/ServiceLogin?continue=x">Sign in</a></div>',
  ]) {
    const other = page(html);
    try { assert.ok(!other.messages.some(m => m?.event === 'signedOut'), html); } finally { other.dom.window.close(); }
  }
});
