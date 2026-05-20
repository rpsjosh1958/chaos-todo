# chaos.tasks

A todo app where your tasks float around the screen, grow bigger and redder the longer you ignore them, and quietly judge you via watermark. Drag to the done zone when you're ready. Or don't.

![Dart](https://img.shields.io/badge/Dart-0175C2?style=flat&logo=dart&logoColor=white)
![Jaspr](https://img.shields.io/badge/Jaspr-web_framework-blue?style=flat)

---

## What it does

- Tasks appear as floating pills and drift around the screen
- Each pill grows uniformly and turns red the longer it goes untouched — font, padding, and all
- Cheeky watermark messages react to what you're doing: adding tasks fast, ignoring everything, completing a streak, being idle, pressing Escape
- Drag a pill to the done circle (bottom-right) to complete it — it spirals in and disappears
- Double-click a pill to panic it: it shudders and bolts
- Escape freezes everything briefly
- A tweaks panel lets you control drift speed, growth rate, and the stress threshold

---

## How it's built

The whole thing is written in **Dart**, not JavaScript.

**[Jaspr](https://github.com/schultek/jaspr)** is the component framework — think React but Dart. It manages the virtual DOM for structural changes: adding and removing tasks, toggling the tweaks panel, swapping the background colour when stress levels shift. Jaspr compiles the Dart component tree to JavaScript and handles reconciliation.

**[`universal_web`](https://pub.dev/packages/universal_web)** provides strongly-typed Dart bindings to browser APIs — `document`, `window`, `MouseEvent`, `HTMLElement` and so on — so you get real autocomplete and type safety instead of raw `js.context` calls.

**The interesting architectural split:** Jaspr only re-renders on structural changes. The 60fps physics loop bypasses the virtual DOM entirely — it calls `document.getElementById` and `el.setAttribute` directly each frame so pills move smoothly without triggering component rebuilds. This keeps animation buttery while Jaspr still owns the component tree.

**CSS does most of the visual UX:**
- `transform: translate3d() scale()` positions and uniformly scales each pill
- `transition` on the canvas background handles the two-level stress colour fade
- `animation` drives the onboarding hint bubbles (fade in, hold, fade out)
- `transform-origin: center` makes pills grow from their own centre
- `will-change: transform` hints the browser to GPU-composite each pill

---

## Running locally

```bash
# requires Flutter/Dart SDK and jaspr_cli
export PATH="/path/to/flutter/bin:$HOME/.pub-cache/bin:$PATH"
dart pub global activate jaspr_cli

jaspr serve
# → http://localhost:8080
```

## Building for production

```bash
jaspr build
# output in build/jaspr/
```

---

## Stack

| Thing | What it does |
|---|---|
| Dart | Language — compiles to JS |
| [Jaspr](https://github.com/schultek/jaspr) | Component framework, virtual DOM, SSR-optional |
| [universal_web](https://pub.dev/packages/universal_web) | Typed Dart bindings to browser Web APIs |
| HTML + CSS | Transforms, transitions, animations, layout |
