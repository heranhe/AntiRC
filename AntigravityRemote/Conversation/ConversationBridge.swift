import Foundation

public struct ConversationMessage: Identifiable, Equatable, Codable {
    public let id: String
    public let role: String
    public let text: String

    public init(id: String = UUID().uuidString, role: String, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }
}

public struct RemoteConversation: Identifiable, Equatable, Codable {
    public let id: String
    public let title: String
    public let time: String
    public let selected: Bool
}

public struct RemoteProject: Identifiable, Equatable, Codable {
    public let id: String
    public let title: String
    public let conversations: [RemoteConversation]
    public let overflow: String
}

public struct RemoteModelOption: Identifiable, Equatable, Codable {
    public let id: String
    public let label: String
    public let selected: Bool
    public var disabled: Bool? = nil
    public var hasChildren: Bool? = nil
}

public struct UsageBucket: Identifiable, Equatable, Codable {
    public let id: String
    public let label: String
    public let detail: String
    public let percent: Int?
}

public struct UsageGroup: Identifiable, Equatable, Codable {
    public let id: String
    public let name: String
    public let buckets: [UsageBucket]
}

public struct WorkspaceSnapshot: Equatable, Codable {
    public let model: String
    public let projects: [RemoteProject]
    public let models: [RemoteModelOption]
    public let usage: [UsageGroup]
}

public struct ConversationSnapshot: Decodable {
    public let messages: [ConversationMessage]
    public let supported: Bool
    public let canSend: Bool
    public let isRunning: Bool
    public let canStop: Bool
    public let workspace: WorkspaceSnapshot?

    private enum CodingKeys: String, CodingKey {
        case messages, supported, canSend, isRunning, canStop, workspace
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        messages = try container.decode([ConversationMessage].self, forKey: .messages)
        supported = try container.decode(Bool.self, forKey: .supported)
        canSend = try container.decode(Bool.self, forKey: .canSend)
        isRunning = try container.decode(Bool.self, forKey: .isRunning)
        canStop = try container.decode(Bool.self, forKey: .canStop)
        workspace = try container.decodeIfPresent(WorkspaceSnapshot.self, forKey: .workspace)
    }
}

/// Converts the official Antigravity Remote Control conversation DOM into a
/// native snapshot. Automatic discovery is restricted to the official host.
public enum ConversationBridge {
    public static let script = #"""
    (() => {
      if (window.__antiConversation) return;

      const official = /(^|\.)antigravity\.google\.com$/i.test(location.hostname) ||
        location.hostname === 'antigravity.google.com';
      const visible = el => !!el && el.getClientRects().length > 0 &&
        getComputedStyle(el).visibility !== 'hidden' && getComputedStyle(el).display !== 'none';
      // Each frame publishes independently; actions must target that same document.
      const queryAll = selector => [...document.querySelectorAll(selector)];
      const present = elements => elements.find(visible) || elements.find(el => !!el) || null;
      const conversationView = () => present(queryAll('[data-testid="conversation-view"]'));
      const legacyRoot = () => document.querySelector('[data-cascade-id]');
      // A conversation row also carries data-cascade-id. It is not the thread.
      const root = () => {
        const view = conversationView();
        if (view) return view;
        const legacy = legacyRoot();
        const testid = legacy?.getAttribute?.('data-testid') || '';
        if (!legacy || testid.startsWith('conversation-row') || testid.startsWith('subagent-')) return null;
        return legacy;
      };
      const input = () => {
        const lexical = present(queryAll('[data-lexical-editor="true"]'));
        const selectors = lexical || official
          ? '[data-lexical-editor="true"][contenteditable="true"], [contenteditable="true"]'
          : '[data-native-composer], #prompt-textarea, textarea[data-testid="chat-input"]';
        return present(queryAll(selectors).filter(el =>
          !el.closest('[aria-hidden="true"], [inert], [role="dialog"]')));
      };
      const composer = () => {
        const el = input();
        let ancestor = el?.parentElement;
        while (ancestor && ancestor !== document.body) {
          if (ancestor.querySelector('input[type="file"]') &&
              ancestor.querySelector('[data-testid="model-selector-trigger"]')) return ancestor;
          ancestor = ancestor.parentElement;
        }
        return el?.closest('form, [class*="input-container"], [class*="input-box"]') ||
          el?.parentElement?.parentElement || el?.parentElement || null;
      };
      const send = () => {
        const scope = composer() || root() || document;
        const selectors = official || document.querySelector('[data-lexical-editor="true"]')
          ? 'button[data-testid="send-button"], button[aria-label="Send message"], button[aria-label*="Send"]'
          : '[data-native-send], button[data-testid="send-button"]';
        const local = [...scope.querySelectorAll(selectors)];
        return present(local.length ? local : queryAll(selectors));
      };
      const stop = () => {
        const scope = composer() || root();
        if (!scope) return null;
        const selectors = official
          ? 'button[data-tooltip-id="input-send-button-cancel-tooltip"], button[aria-label^="Cancel ("]'
          : '[data-native-stop], button[data-testid="stop-button"]';
        return [...scope.querySelectorAll(selectors)].find(visible);
      };

      const elementIDs = new WeakMap();
      const pageID = Math.random().toString(36).slice(2);
      let nextID = 0, previous = '', timer;
      const id = el => {
        if (!elementIDs.has(el)) elementIDs.set(el, `${pageID}-${++nextID}`);
        return elementIDs.get(el);
      };
      const topmost = elements => elements.filter(el =>
        !elements.some(other => other !== el && other.contains(el)));
      const text = source => {
        const clone = source.cloneNode(true);
        clone.querySelectorAll([
          'button', 'script', 'style', 'svg', '[aria-hidden="true"]',
          '[data-tooltip-id]', '[data-testid="queued-decorators"]',
          '.user-input-buttons-container'
        ].join(',')).forEach(el => el.remove());
        clone.querySelectorAll('pre').forEach(pre => {
          const code = pre.querySelector('code');
          const lang = (code?.className || '').match(/language-([\w+-]+)/)?.[1] || '';
          pre.replaceWith(document.createTextNode('\n```' + lang + '\n' +
            (code || pre).textContent + '\n```\n'));
        });
        clone.querySelectorAll('br').forEach(el =>
          el.replaceWith(document.createTextNode('\n')));
        clone.querySelectorAll('p, li, h1, h2, h3, h4, blockquote').forEach(el =>
          el.appendChild(document.createTextNode('\n\n')));
        return clone.textContent.replace(/\n[ \t]+/g, '\n')
          .replace(/\n{3,}/g, '\n\n').trim();
      };

      const officialEntries = scope => {
        const users = [...scope.querySelectorAll('[data-testid="user-input-step"]')]
          .filter(visible).map(el => ({ el, role: 'user' }));
        const markdown = topmost([...scope.querySelectorAll(
          '.rendered-markdown, .markdown-content, .chat-markdown-part'
        )].filter(el => visible(el) &&
          !el.closest('[data-testid="user-input-step"]') &&
          !el.closest('[data-testid="pending-user-messages"]') &&
          !el.closest('form, [class*="input-container"], [class*="input-box"]')))
          .map(el => ({ el, role: 'assistant' }));
        return [...users, ...markdown].sort((a, b) => a.el === b.el ? 0 :
          a.el.compareDocumentPosition(b.el) & Node.DOCUMENT_POSITION_FOLLOWING ? -1 : 1);
      };
      const semanticEntries = scope => {
        const selector = '[data-message-author-role], [data-message-role]';
        return [...scope.querySelectorAll(selector)].filter(el => {
          const role = el.getAttribute('data-message-author-role') ||
            el.getAttribute('data-message-role');
          return ['user', 'assistant', 'system', 'tool'].includes(role) &&
            !el.parentElement?.closest(selector);
        }).map(el => ({
          el: el.querySelector('[data-message-content], .markdown, .message-content') || el,
          role: el.getAttribute('data-message-author-role') || el.getAttribute('data-message-role')
        }));
      };
      const clean = value => (value || '').replace(/\s+/g, ' ').trim();
      const rowTitle = row => clean(row.querySelector('a')?.getAttribute('aria-label')) ||
        clean(row.querySelector('span')?.textContent) || '未命名对话';
      const rowTime = row => [...row.querySelectorAll('span')].map(el => clean(el.textContent))
        .find(value => /^(now|\d+(?:\s*[smhdw]|mo|y))$/i.test(value)) || '';
      const projects = () => {
        const nodes = queryAll('[data-testid="section-header"], [data-testid^="conversation-row-"], [data-cascade-id]')
          .filter(el => {
            const testid = el.getAttribute('data-testid') || '';
            if (testid === 'conversation-view' || testid.startsWith('subagent-')) return false;
            if (el.closest('[data-testid="conversation-view"]')) return false;
            if (testid === 'section-header' || testid.startsWith('conversation-row-')) return true;
            return !!el.getAttribute('data-cascade-id') &&
              !el.parentElement?.closest('[data-cascade-id]');
          });
        const groups = [];
        const seen = new Set();
        let current = null;
        const ensure = () => {
          if (current) return current;
          current = { id: 'conversations', title: '对话', conversations: [], overflow: '' };
          groups.push(current);
          return current;
        };
        for (const node of nodes) {
          if (node.getAttribute('data-testid') === 'section-header') {
            const title = node.getAttribute('data-title') || clean(node.textContent) || '项目';
            current = { id: `${title}-${groups.length}`, title, conversations: [], overflow: '' };
            groups.push(current);
            continue;
          }
          const cascadeId = node.getAttribute('data-cascade-id') || '';
          if (!cascadeId || seen.has(cascadeId)) continue;
          seen.add(cascadeId);
          ensure().conversations.push({
            id: cascadeId,
            title: rowTitle(node),
            time: rowTime(node),
            selected: node.getAttribute('data-selected') === 'true'
          });
        }
        const buttons = queryAll('button').filter(button =>
          /^(See all|See less)\b/.test(clean(button.textContent)));
        if (typeof Node !== 'undefined') {
          for (const button of buttons) {
            let owner = null;
            for (const header of queryAll('[data-testid="section-header"]')) {
              if (header.compareDocumentPosition(button) & Node.DOCUMENT_POSITION_FOLLOWING) owner = header;
            }
            const title = owner?.getAttribute('data-title') || '';
            const group = groups.find(item => item.title === title) || groups[groups.length - 1];
            if (group && !group.overflow) group.overflow = clean(button.textContent);
          }
        }
        return groups.filter(group => group.conversations.length > 0 || group.overflow);
      };
      const modelTrigger = () => present(queryAll('[data-testid="model-selector-trigger"]'));
      const modelLabel = () => {
        const trigger = modelTrigger();
        if (!trigger) return '';
        return clean(trigger.querySelector('span')?.innerText || trigger.innerText);
      };
      const modelOptions = () => {
        const efforts = queryAll('[data-testid="model-selector-effort-option"]').filter(visible);
        const nodes = efforts.length ? efforts : queryAll('[data-testid="model-selector-item"], [data-testid="model-selector-effort-group"]').filter(visible);
        return nodes.map(el => {
          const control = el.closest('[role="menuitem"], [role="menuitemradio"], button') || el;
          const base = el.getAttribute('data-model-base');
          const effort = el.getAttribute('data-effort');
          const idValue = base ? 'group:' + base : effort ? 'effort:' + effort : el.getAttribute('data-model-label') || '';
          const label = clean(el.innerText) || idValue;
          return {
            id: idValue || label,
            label,
            disabled: control.getAttribute('aria-disabled') === 'true' || !!control.disabled,
            hasChildren: !!base,
            selected: control.getAttribute('aria-checked') === 'true' ||
              control.getAttribute('aria-selected') === 'true' ||
              control.getAttribute('data-selected') === 'true' ||
              control.getAttribute('data-state') === 'checked'
          };
        }).filter(option => option.id);
      };
      const usageGroups = () => {
        const circles = queryAll('[data-testid="quota-progress-circle"]');
        const groups = [];
        const groupName = host => {
          let node = host;
          for (let depth = 0; depth < 8 && node; depth += 1) {
            let previous = node.previousElementSibling;
            while (previous) {
              const text = clean(previous.innerText).split('\n')[0];
              const hasMeter = !!previous.querySelector('[data-testid="quota-progress-circle"]') ||
                text.includes('%');
              if (text && !hasMeter && text.length < 80) return text;
              previous = previous.previousElementSibling;
            }
            node = node.parentElement;
          }
          return '用量';
        };
        for (const circle of circles) {
          let host = circle.parentElement;
          for (let depth = 0; depth < 6 && host; depth += 1) {
            const alone = host.querySelectorAll('[data-testid="quota-progress-circle"]').length === 1;
            if (alone && (host.innerText || '').includes('%') && host.querySelectorAll('span').length >= 2) break;
            host = host.parentElement;
          }
          if (!host) continue;
          const spans = [...host.querySelectorAll('span')].map(el => clean(el.textContent)).filter(Boolean);
          const percentText = spans.find(value => /^\d+%$/.test(value));
          const label = spans.find(value => value !== percentText && !/^Resets\b/i.test(value)) || '';
          const detail = spans.find(value => value !== label && value !== percentText) || '';
          if (!label) continue;
          const name = groupName(host);
          let group = groups.find(item => item.name === name);
          if (!group) {
            group = { id: name, name, buckets: [] };
            groups.push(group);
          }
          const bucketId = `${name}:${label}`;
          if (group.buckets.some(bucket => bucket.id === bucketId)) continue;
          group.buckets.push({
            id: bucketId,
            label,
            detail,
            percent: percentText ? Number.parseInt(percentText, 10) : null
          });
        }
        return groups;
      };
      const snapshot = () => {
        const scope = root();
        const entries = scope ? (official ? officialEntries(scope) : semanticEntries(scope)) : [];
        const messages = entries.map(entry => ({
          id: id(entry.el), role: entry.role, text: text(entry.el)
        })).filter(message => message.text.length > 0);
        const editor = input(), submit = send(), cancel = stop();
        return {
          frameID: pageID,
          messages,
          supported: !!scope && (!!editor || messages.length > 0),
          canSend: !!editor && !!submit && !editor.disabled && !editor.readOnly &&
            submit.getAttribute('aria-disabled') !== 'true',
          isRunning: !!cancel,
          canStop: !!cancel && !cancel.disabled && cancel.getAttribute('aria-disabled') !== 'true',
          workspace: {
            model: modelLabel(),
            projects: projects(),
            models: modelOptions(),
            usage: usageGroups()
          }
        };
      };
      const publish = () => {
        let state;
        try { state = snapshot(); } catch (e) { return; }
        const encoded = JSON.stringify(state);
        if (!encoded || encoded === previous) return;
        previous = encoded;
        try { window.webkit.messageHandlers.conversation.postMessage(JSON.parse(encoded)); }
        catch (e) {}
      };
      const setText = (editor, value) => {
        editor.focus();
        if (editor instanceof HTMLTextAreaElement || editor instanceof HTMLInputElement) {
          const proto = editor instanceof HTMLTextAreaElement
            ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
          Object.getOwnPropertyDescriptor(proto, 'value').set.call(editor, value);
          editor.dispatchEvent(new InputEvent('input', {
            bubbles: true, inputType: 'insertText', data: value
          }));
          editor.dispatchEvent(new Event('change', { bubbles: true }));
          return true;
        }
        if (!editor.isContentEditable) return false;
        const selection = document.getSelection();
        selection?.selectAllChildren(editor);
        if (document.execCommand('insertText', false, value)) return true;
        editor.textContent = value;
        editor.dispatchEvent(new InputEvent('input', {
          bubbles: true, inputType: 'insertText', data: value
        }));
        return editor.textContent === value;
      };

      const waitFor = async predicate => {
        for (let attempt = 0; attempt < 30; attempt++) {
          if (predicate()) { publish(); return true; }
          await new Promise(resolve => setTimeout(resolve, 100));
        }
        publish();
        return false;
      };
      const activate = element => {
        if (!element || element.disabled || element.getAttribute('aria-disabled') === 'true') return false;
        // Menu triggers listen on pointerdown rather than HTMLElement.click().
        if (element.getAttribute('aria-haspopup') === 'menu') {
          element.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true, button: 0, pointerType: 'mouse', isPrimary: true }));
          element.dispatchEvent(new PointerEvent('pointerup', { bubbles: true, button: 0, pointerType: 'mouse', isPrimary: true }));
        } else element.click();
        return true;
      };

      window.__antiConversation = {
        async send(value) {
          const editor = input();
          if (!editor || !send() || stop()) return 'unavailable';
          const existing = editor.isContentEditable ? editor.textContent : editor.value;
          if (existing?.trim() && existing !== value) return 'draft-conflict';
          if (!existing?.trim() && !setText(editor, value)) return 'unsupported';
          await new Promise(resolve => setTimeout(resolve, 180));
          const submit = send();
          if (!submit || submit.disabled || submit.getAttribute('aria-disabled') === 'true') {
            return 'draft-staged';
          }
          submit.click();
          publish();
          return 'submitted';
        },
        stop() {
          const cancel = stop();
          if (!cancel || cancel.disabled || cancel.getAttribute('aria-disabled') === 'true') return false;
          cancel.click();
          return true;
        },
        newConversation(projectTitle) {
          let btn = null;
          if (projectTitle) {
            const headers = [...document.querySelectorAll('[data-testid="section-header"]')];
            const header = headers.find(item => item.getAttribute('data-title') === projectTitle || clean(item.textContent).includes(projectTitle));
            if (header) {
              btn = header.querySelector('button, [role="button"]');
            }
          }
          if (!btn) {
            const candidates = [...document.querySelectorAll('button, [role="button"]')].filter(visible);
            btn = candidates.find(b => {
              const label = b.getAttribute('aria-label') || b.getAttribute('data-testid') || clean(b.textContent);
              return /new conversation|new chat|新建对话|新建会话/i.test(label);
            });
          }
          if (btn) {
            btn.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true, button: 0, pointerType: 'mouse', isPrimary: true }));
            btn.dispatchEvent(new PointerEvent('pointerup', { bubbles: true, button: 0, pointerType: 'mouse', isPrimary: true }));
            btn.click();
          } else {
            const active = document.activeElement || document.body;
            active.dispatchEvent(new KeyboardEvent('keydown', { key: 'n', code: 'KeyN', ctrlKey: true, metaKey: true, bubbles: true }));
          }
          setTimeout(() => {
            const ed = input();
            if (ed) {
              ed.focus();
              ed.scrollIntoView({ behavior: 'smooth', block: 'center' });
            }
          }, 300);
          publish();
          return true;
        },
        openConversation(cascadeId) {
          const escaped = window.CSS?.escape ? CSS.escape(String(cascadeId)) : String(cascadeId).replace(/["\\\]\[]/g, '');
          const row = document.querySelector(`[data-testid^="conversation-row-"][data-cascade-id="${escaped}"]`);
          const link = row?.querySelector('a') || row;
          if (!link) return false;
          link.click();
          return true;
        },
        expandProject(title) {
          const headers = [...document.querySelectorAll('[data-testid="section-header"]')];
          const header = headers.find(item => item.getAttribute('data-title') === title);
          const buttons = [...document.querySelectorAll('button')].filter(button =>
            visible(button) && /^(See all|See less)\b/.test(clean(button.textContent)));
          let chosen = null;
          if (header && typeof Node !== 'undefined') {
            chosen = buttons.find(button =>
              header.compareDocumentPosition(button) & Node.DOCUMENT_POSITION_FOLLOWING) || null;
          }
          (chosen || buttons[0])?.click();
          return !!(chosen || buttons[0]);
        },
        async openModels() {
          const effort = queryAll('[data-testid="model-selector-effort-option"]').find(visible);
          if (effort) {
            const control = effort.closest('[role="menuitemradio"], [role="menuitem"], button') || effort;
            control.focus();
            control.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowLeft', code: 'ArrowLeft', bubbles: true }));
            await waitFor(() => !queryAll('[data-testid="model-selector-effort-option"]').some(visible));
          }
          const panel = document.querySelector('[data-testid="model-selector-panel"]');
          if (panel && visible(panel)) { previous = ''; publish(); return true; }
          const trigger = modelTrigger();
          if (!trigger) return false;
          activate(trigger);
          previous = '';
          return await waitFor(() => modelOptions().length > 0);
        },
        async selectModel(label) {
          if (label.startsWith('group:')) {
            const group = queryAll('[data-testid="model-selector-effort-group"]')
              .find(el => el.getAttribute('data-model-base') === label.slice(6));
            const control = group?.closest('[role="menuitem"], button');
            if (!control) return false;
            control.focus();
            control.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowRight', code: 'ArrowRight', bubbles: true }));
            return await waitFor(() => queryAll('[data-testid="model-selector-effort-option"]').some(visible));
          }
          if (label.startsWith('effort:')) {
            const effort = queryAll('[data-testid="model-selector-effort-option"]')
              .find(el => el.getAttribute('data-effort') === label.slice(7));
            if (!activate(effort?.closest('[role="menuitemradio"], [role="menuitem"], button') || effort)) return false;
            return await waitFor(() => !queryAll('[data-testid="model-selector-panel"]').some(visible));
          }
          const item = [...document.querySelectorAll('[data-testid="model-selector-item"]')]
            .find(el => el.getAttribute('data-model-label') === label || clean(el.innerText) === label);
          if (!activate(item)) return false;
          return await waitFor(() => !queryAll('[data-testid="model-selector-panel"]').some(visible));
        },
        async openUsage() {
          if (!document.querySelector('[data-testid="quota-progress-circle"]')) {
            if (!await this.openModels()) return false;
            const view = [...document.querySelectorAll('[role="menuitem"], button, span, a')]
              .filter(visible)
              .find(el => clean(el.textContent) === 'View Usage');
            const control = view?.closest('[role="menuitem"], button, a') || view;
            if (!control) return false;
            control.focus();
            control.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowRight', code: 'ArrowRight', bubbles: true }));
          }
          publish();
          previous = '';
          return await waitFor(() => usageGroups().length > 0);
        },
        attachMedia() {
          const field = composer()?.querySelector('input[type="file"]');
          if (!field) return false;
          field.click();
          return true;
        },
        async attachImage(payload) {
          const scope = composer();
          const field = scope?.querySelector('input[type="file"]');
          if (!field || field.disabled || !payload?.base64 || !payload.type?.startsWith('image/')) return false;
          const bytes = Uint8Array.from(atob(payload.base64), character => character.charCodeAt(0));
          const file = new File([bytes], payload.name, { type: payload.type });
          const transfer = new DataTransfer();
          transfer.items.add(file);
          field.files = transfer.files;
          field.dispatchEvent(new Event('change', { bubbles: true }));
          // The page owns validation and uploading. A selected file is not proof of server acceptance.
          publish();
          return true;
        },
        async closePanels() {
          for (let attempt = 0; attempt < 4; attempt++) {
            if (!queryAll('[data-testid="model-selector-panel"]').some(visible)) return true;
            const focused = document.activeElement || document.body;
            focused.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', code: 'Escape', bubbles: true }));
            await new Promise(resolve => setTimeout(resolve, 100));
          }
          return !queryAll('[data-testid="model-selector-panel"]').some(visible);
        },
        refresh: publish
      };
      if (document.documentElement) {
        new MutationObserver(() => {
          if (timer) return;
          timer = setTimeout(() => { timer = null; publish(); }, 100);
        }).observe(document.documentElement, {
          subtree: true, childList: true, characterData: true, attributes: true
        });
      }
      document.addEventListener('click', function(e) {
        const btn = e.target.closest('button, [role="button"]');
        if (btn) {
          const inHeader = btn.closest('[data-testid="section-header"]');
          const isNew = /new|add|新建|加/i.test(btn.getAttribute('aria-label') || btn.getAttribute('data-testid') || '');
          if (inHeader || isNew) {
            setTimeout(() => {
              const ed = input();
              if (ed) {
                ed.focus();
                ed.scrollIntoView({ behavior: 'smooth', block: 'center' });
              }
            }, 300);
          }
        }
      }, { capture: false, passive: true });

      publish();
      if (typeof setInterval === 'function') setInterval(publish, 700);
    })();
    """#
}
