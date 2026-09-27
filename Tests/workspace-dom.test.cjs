const { test } = require('node:test');
const assert = require('node:assert/strict');
const { JSDOM } = require('jsdom');
const fs = require('node:fs');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, '../AntigravityRemote/Conversation/ConversationBridge.swift'), 'utf8').split('static let script = #"""')[1].split('"""#')[0];

// DOM contracts taken from the installed official toolkit. This tests bridge behavior,
// not the remote service, Radix implementation, or server-side upload acceptance.
function fixture(t) {
  const dom = new JSDOM(`<main>
    <section data-testid="conversation-view" data-cascade-id="thread">
      <form><div data-lexical-editor="true" contenteditable="true"></div>
        <input type="file" accept="image/*"><button data-testid="send-button">Send</button>
        <button data-testid="model-selector-trigger" aria-haspopup="menu"><span>Gemini Medium</span></button>
      </form>
    </section>
  </main>`, { url: 'https://antigravity.google.com/r/test', runScripts: 'outside-only' });
  t.after(() => dom.window.close());
  const w = dom.window, d = w.document, snapshots = [];
  w.HTMLElement.prototype.getClientRects = function () { return this.hidden ? [] : [{}]; };
  Object.defineProperty(w.HTMLElement.prototype, 'innerText', { get() { return this.textContent; } });
  w.PointerEvent = w.MouseEvent;
  w.webkit = { messageHandlers: { conversation: { postMessage: s => snapshots.push(s) } } };
  const trigger = d.querySelector('[data-testid="model-selector-trigger"]');
  let pointerOpens = 0;
  trigger.addEventListener('pointerdown', () => {
    pointerOpens++;
    if (d.querySelector('[data-testid="model-selector-panel"]')) return;
    const panel = d.createElement('div');
    panel.dataset.testid = 'model-selector-panel';
    panel.innerHTML = `<div role="menuitem" data-testid="model-selector-item" data-model-label="Basic">Basic</div>
      <div role="menuitem" data-testid="model-selector-item" data-model-label="Unavailable" aria-disabled="true">Unavailable</div>
      <div role="menuitem" id="group"><span data-testid="model-selector-effort-group" data-model-base="Gemini">Gemini Medium</span></div>
      <div role="menuitem" id="usage"><span>View Usage</span></div>`;
    d.body.append(panel);
    panel.addEventListener('keydown', e => { if (e.key === 'Escape') panel.remove(); });
    panel.querySelector('[data-model-label="Basic"]').onclick = () => {
      trigger.querySelector('span').textContent = 'Basic'; panel.remove();
    };
    panel.querySelector('#group').addEventListener('keydown', e => {
      if (e.key !== 'ArrowRight') return;
      const sub = d.createElement('div');
      sub.innerHTML = `<div role="menuitemradio" aria-checked="true"><span data-testid="model-selector-effort-option" data-effort="medium">Medium</span></div>
        <div role="menuitemradio"><span data-testid="model-selector-effort-option" data-effort="high">High</span></div>`;
      panel.append(sub);
      sub.addEventListener('keydown', e => { if (e.key === 'ArrowLeft') sub.remove(); });
      sub.addEventListener('click', e => {
        const item = e.target.closest('[role="menuitemradio"]');
        if (!item) return;
        trigger.querySelector('span').textContent = `Gemini ${item.textContent}`; panel.remove();
      });
    });
    panel.querySelector('#usage').addEventListener('keydown', e => {
      if (e.key !== 'ArrowRight') return;
      const usage = d.createElement('section');
      usage.innerHTML = `<h3>Gemini</h3><div><span>Daily</span><span>Resets tomorrow</span><span>73%</span><svg><circle data-testid="quota-progress-circle"></circle></svg></div>`;
      panel.append(usage);
    });
  });
  w.eval(source);
  return { w, d, bridge: w.__antiConversation, snapshots, pointerOpens: () => pointerOpens };
}

test('opens pointer-triggered model menu and includes disabled + effort group rows', async t => {
  const f = fixture(t);
  assert.equal(await f.bridge.openModels(), true);
  assert.equal(f.pointerOpens(), 1);
  const options = f.snapshots.at(-1).workspace.models;
  assert.deepEqual(Array.from(options, x => x.id), ['Basic', 'Unavailable', 'group:Gemini']);
  assert.equal(options[1].disabled, true);
  assert.equal(options[2].hasChildren, true);
  assert.equal(await f.bridge.selectModel('Unavailable'), false);
});

test('effort navigation does not select the group prematurely and confirms choice', async t => {
  const f = fixture(t);
  await f.bridge.openModels();
  assert.equal(await f.bridge.selectModel('group:Gemini'), true);
  assert.equal(f.snapshots.at(-1).workspace.model, 'Gemini Medium');
  assert.deepEqual(Array.from(f.snapshots.at(-1).workspace.models, x => x.id), ['effort:medium', 'effort:high']);
  assert.equal(await f.bridge.selectModel('effort:high'), true);
  assert.equal(f.snapshots.at(-1).workspace.model, 'Gemini High');
});

test('returning from effort submenu restores full model list', async t => {
  const f = fixture(t);
  await f.bridge.openModels(); await f.bridge.selectModel('group:Gemini');
  assert.equal(await f.bridge.openModels(), true);
  assert.equal(f.snapshots.at(-1).workspace.models.length, 3);
});

test('usage opens the submenu and republishes current quota after cache reset', async t => {
  const f = fixture(t);
  assert.equal(await f.bridge.openUsage(), true);
  const bucket = f.snapshots.at(-1).workspace.usage[0].buckets[0];
  assert.equal(bucket.label, 'Daily'); assert.equal(bucket.percent, 73);
  assert.equal(bucket.detail, 'Resets tomorrow');
  const count = f.snapshots.length;
  assert.equal(await f.bridge.openUsage(), true);
  assert.ok(f.snapshots.length > count);
});

test('empty active page publishes cleared state rather than retaining old conversation', async t => {
  const f = fixture(t);
  f.d.body.replaceChildren(); f.bridge.refresh();
  assert.equal(f.snapshots.at(-1).supported, false);
  assert.equal(f.snapshots.at(-1).canSend, false);
  assert.equal(f.snapshots.at(-1).workspace.model, '');
});

test('image handoff targets composer input instead of unrelated file forms', async t => {
  const f = fixture(t);
  const unrelated = f.d.createElement('input'); unrelated.type = 'file';
  f.d.body.prepend(unrelated);
  let changes = 0;
  const field = f.d.querySelector('form input');
  Object.defineProperty(field, 'files', { writable: true, value: [] });
  field.addEventListener('change', () => changes++);
  f.w.DataTransfer = class {
    files = [];
    items = { add: file => this.files.push(file) };
  };
  assert.equal(await f.bridge.attachImage({ name: 'test.png', type: 'image/png', base64: 'YWJj' }), true);
  assert.equal(changes, 1); assert.equal(field.files[0].name, 'test.png');
  assert.equal(unrelated.files.length, 0);
  assert.equal(await f.bridge.attachImage({ name: 'script.js', type: 'text/javascript', base64: 'YWJj' }), false);
});

test('closing the native sheet dismisses the web menu instead of leaving it over the composer', async t => {
  const f = fixture(t);
  await f.bridge.openModels();
  const item = f.d.querySelector('[data-model-label="Basic"]');
  item.tabIndex = 0; item.focus();
  assert.equal(await f.bridge.closePanels(), true);
  assert.equal(f.d.querySelector('[data-testid="model-selector-panel"]'), null);
});
