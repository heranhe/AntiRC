// Run: node --test Tests/conversation-bridge.test.cjs
const { test } = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const source = fs.readFileSync(require('node:path').join(__dirname, '../AntigravityRemote/Conversation/ConversationBridge.swift'), 'utf8').split('static let script = #"""')[1].split('"""#')[0];

test('tracks the selectors shipped by the Antigravity 2.0 conversation toolkit', () => {
    for (const selector of [
        'data-testid="conversation-view"',
        'data-testid="user-input-step"',
        'data-lexical-editor="true"',
        'data-testid="send-button"',
        'input-send-button-cancel-tooltip'
    ]) assert.equal(source.includes(selector), true, `missing official selector: ${selector}`);
});

function page({ supported = true, draft = '', disabled = false, running = false } = {}) {
    const snapshots = [];
    let sends = 0, stops = 0, observer;
    class Textarea {
        constructor() { this._value = draft; }
        get value() { return this._value; }
        set value(value) { this._value = value; }
        getClientRects() { return [1]; }
        dispatchEvent() {}
        focus() {}
        closest(selector) {
            return selector.includes('role="dialog"') ? null : scope;
        }
    }
    const input = new Textarea();
    const button = { disabled, getClientRects: () => [1], getAttribute: () => null, click: () => sends++ };
    const stop = { ...button, disabled: false, click: () => stops++ };
    const query = selector => {
        if (selector.includes('data-message-author-role')) return [];
        if (!supported) return [];
        if (selector.includes('data-native-composer')) return [input];
        if (selector.includes('data-native-send')) return [button];
        if (selector.includes('data-native-stop')) return running ? [stop] : [];
        return [];
    };
    const scope = { querySelectorAll: query };
    const root = { querySelectorAll: query };
    const window = { webkit: { messageHandlers: { conversation: { postMessage: state => snapshots.push(state) } } } };
    const context = {
        window,
        location: { hostname: 'example.test' },
        document: {
            documentElement: {},
            querySelector(selector) {
                if (selector.includes('conversation-view')) return null;
                if (selector.includes('data-cascade-id')) return supported ? root : null;
                return null;
            },
            querySelectorAll: query
        },
        HTMLTextAreaElement: Textarea, HTMLInputElement: class {},
        getComputedStyle: () => ({ visibility: 'visible' }),
        InputEvent: class {}, Event: class {},
        MutationObserver: class { constructor(callback) { observer = callback; } observe() {} },
        setTimeout, WeakMap, Math
    };
    vm.runInNewContext(source, context);
    return { bridge: window.__antiConversation, input, snapshots, sends: () => sends, stops: () => stops, observer, context };
}

test('unknown pages disable native sending and never submit an arbitrary form', async () => {
    const p = page({ supported: false });
    assert.equal(p.snapshots[0].supported, false);
    assert.equal(p.snapshots[0].canSend, false);
    assert.equal(await p.bridge.send('hello'), 'unavailable');
    assert.equal(p.sends(), 0);
});

test('message payload remains literal, including quotes and JavaScript syntax', async () => {
    const p = page();
    const text = "你好\n```swift\nprint(\"test\")\n```\n'); window.attacked = true; //";
    assert.equal(await p.bridge.send(text), 'submitted');
    assert.equal(p.input.value, text);
    assert.equal(p.context.window.attacked, undefined);
    assert.equal(p.sends(), 1);
});

test('existing web drafts are preserved and repeated dispatch cannot duplicate them', async () => {
    const p = page({ draft: 'existing draft' });
    assert.equal(await p.bridge.send('replacement'), 'draft-conflict');
    assert.equal(p.input.value, 'existing draft');
    assert.equal(p.sends(), 0);
});

test('disabled send keeps the staged text without reporting submission', async () => {
    const p = page({ disabled: true });
    assert.equal(await p.bridge.send('keep this'), 'draft-staged');
    assert.equal(p.input.value, 'keep this');
    assert.equal(p.sends(), 0);
});

test('retrying an identical staged draft does not append or reject that draft', async () => {
    const p = page({ draft: 'staged draft' });
    assert.equal(await p.bridge.send('staged draft'), 'submitted');
    assert.equal(p.input.value, 'staged draft');
    assert.equal(p.sends(), 1);
});

test('running response blocks send and uses only the explicit stop control', async () => {
    const p = page({ running: true });
    assert.equal(p.snapshots[0].isRunning, true);
    assert.equal(await p.bridge.send('hello'), 'unavailable');
    assert.equal(p.bridge.stop(), true);
    assert.equal(p.stops(), 1);
    assert.equal(p.sends(), 0);
});

test('official home reads projects and the real composer, not a conversation row', async () => {
    const snapshots = [];
    const clicked = [];
    const attrs = (node, name) => node.attributes[name] ?? null;
    const matches = (node, selector) => {
        if (selector === 'a') return node.tag === 'a';
        if (selector === 'span') return node.tag === 'span';
        if (selector === 'button') return node.tag === 'button';
        if (selector.includes('section-header') && node.attributes['data-testid'] === 'section-header') return true;
        if (selector.includes('conversation-row-') && String(node.attributes['data-testid'] || '').startsWith('conversation-row-')) return true;
        if (selector.includes('conversation-view') && node.attributes['data-testid'] === 'conversation-view') return true;
        if (selector.includes('data-lexical-editor') && node.attributes['data-lexical-editor'] === 'true') return true;
        if (selector.includes('send-button') && node.attributes['data-testid'] === 'send-button') return true;
        if (selector.includes('data-cascade-id') && !selector.includes('conversation-row-')) return 'data-cascade-id' in node.attributes;
        return false;
    };
    const walk = (node, selector, found = []) => {
        for (const child of node.children || []) {
            if (matches(child, selector)) found.push(child);
            walk(child, selector, found);
        }
        return found;
    };
    const make = (tag, attributes = {}, children = [], text = '') => {
        const node = {
            tag, attributes, children, textContent: text, innerText: text,
            getAttribute: name => attrs(node, name),
            getClientRects: () => [1],
            closest: () => null,
            click() { clicked.push(node.attributes.id || node.attributes['data-testid'] || tag); }
        };
        node.querySelectorAll = selector => walk(node, selector);
        node.querySelector = selector => node.querySelectorAll(selector)[0] || null;
        children.forEach((child, index) => {
            child.parentElement = node;
            child.previousElementSibling = children[index - 1] || null;
        });
        return node;
    };
    const row = make('div', { 'data-testid': 'conversation-row-sidebar', 'data-cascade-id': 'cascade-1', 'data-selected': 'false' }, [
        make('a', { id: 'open-cascade-1', 'aria-label': 'Antigravity 电脑端扫码登录' }),
        make('span', {}, [], 'Antigravity 电脑端扫码登录'),
        make('span', {}, [], '40m')
    ]);
    const header = make('div', { 'data-testid': 'section-header', 'data-title': '反重力App' }, [], '反重力App');
    const seeAll = make('button', { id: 'see-all' }, [], 'See all (27)');
    const editor = make('div', { 'data-lexical-editor': 'true', contenteditable: 'true' });
    editor.disabled = false;
    editor.readOnly = false;
    editor.isContentEditable = true;
    const submit = make('button', { 'data-testid': 'send-button', 'aria-label': 'Send message' });
    submit.disabled = false;
    submit.getAttribute = name => name === 'aria-disabled' ? null : attrs(submit, name);
    const composer = make('form', {}, [editor, submit]);
    editor.closest = selector => selector.includes('dialog') || selector.includes('aria-hidden') || selector.includes('[inert]') ? null : composer;
    const document = make('div', {}, [header, row, seeAll, composer]);
    document.documentElement = document;
    document.querySelector = selector => {
        if (selector.includes('conversation-view')) return null;
        if (selector.includes('data-cascade-id') && !selector.includes('conversation-row-')) return row;
        return walk(document, selector)[0] || null;
    };
    document.querySelectorAll = selector => walk(document, selector);
    header.compareDocumentPosition = () => 4;
    const window = { webkit: { messageHandlers: { conversation: { postMessage: state => snapshots.push(state) } } } };
    vm.runInNewContext(source, {
        window, document, Node: { DOCUMENT_POSITION_FOLLOWING: 4 },
        location: { hostname: 'antigravity.google.com' },
        getComputedStyle: () => ({ visibility: 'visible' }),
        HTMLTextAreaElement: class {}, HTMLInputElement: class {},
        InputEvent: class {}, Event: class {},
        MutationObserver: class { constructor() {} observe() {} },
        setTimeout, WeakMap, Math
    });
    const state = snapshots[0];
    assert.equal(state.supported, false);
    assert.equal(state.messages.length, 0);
    assert.equal(state.canSend, true);
    assert.equal(state.workspace.projects.length, 1);
    const conversation = state.workspace.projects[0].conversations[0];
    assert.equal(state.workspace.projects[0].title, '反重力App');
    assert.equal(conversation.id, 'cascade-1');
    assert.equal(conversation.title, 'Antigravity 电脑端扫码登录');
    assert.equal(conversation.time, '40m');
    assert.equal(conversation.selected, false);
    assert.equal(state.workspace.projects[0].overflow, 'See all (27)');
    assert.equal(window.__antiConversation.openConversation('cascade-1'), true);
    assert.deepEqual(clicked, ['open-cascade-1']);
});

test('bridge installation is idempotent and unchanged snapshots are suppressed', async () => {
    const p = page();
    vm.runInNewContext(source, p.context);
    p.observer();
    p.observer();
    await new Promise(resolve => setTimeout(resolve, 130));
    assert.equal(p.snapshots.length, 1);
});
