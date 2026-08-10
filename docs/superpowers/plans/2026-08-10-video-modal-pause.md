# Video Modal Pause Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every path that closes a video modal stop the video, so navigating away with the Back button no longer leaves audio playing.

**Architecture:** Replace scattered `modalDiv.style.display = 'none'` assignments with one symmetric, video-aware pair — `hideModalItem` and `showModalItem` — and route all navigation paths through them. The `popstate` and `hashchange` handlers collapse into a single idempotent `syncModalsToHash`. The three video-specific function variants are deleted so exactly one open path and one close path remain.

**Tech Stack:** Sinatra 4.2 + ERB templates, jQuery, vanilla browser History API. No build step — `public/js/application.js` is served as-is.

**Spec:** `docs/superpowers/specs/2026-08-10-video-modal-pause-design.md`

## Global Constraints

- **No JS test harness exists, and none is being added.** The suite is minitest + rack-test and cannot observe `video.paused`. Do not add assertions about front-end behavior to `test/smoke_test.rb` — those smoke tests verify the deployable artifact only. Verification for this change is the manual browser checklist in Task 5.
- **Do not modify `test/smoke_test.rb`.** It must still pass unchanged; run it as a regression check that nothing server-side broke.
- **Closing a video resets it to 0:00.** This is existing behavior and is deliberately preserved via `video.load()` on hide. Do not "optimize" the `load()` away.
- **No new dependencies, no build step, no framework changes.** This is a change to one JS file and three ERB templates.
- **Match surrounding code style:** `var` (not `let`/`const`), `function` expressions assigned to `window.*`, jQuery for DOM queries, `!=`/`==` as already used in this file.
- **Indentation warning:** `public/js/application.js` lines 105–117 are indented with a leading **space followed by a tab** (` \t`), unlike the rest of the file which uses two spaces. Any `Edit` targeting that block must reproduce that whitespace exactly in `old_string`, or the match will fail. New replacement code should use two-space indentation to match the file majority.

---

### Task 1: Video-aware show/hide primitives

Introduces `hideModalItem`, makes `showModalItem` video-aware, and points `onModalCancelClick` at the new primitive. After this task the app still works exactly as before — the video-specific functions still exist and still get called. Nothing has been rewired yet.

**Files:**
- Modify: `public/js/application.js:105-117` (`onModalCancelClick`, `onVideoModelCancelClick`)
- Modify: `public/js/application.js:173-176` (`showModalItem`)

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:
  - `window.hideModalItem(modalDiv)` — takes a DOM element (the `.w3-modal` div), returns nothing. Pauses and rewinds any contained `<video>`, sets `display: none`, and nulls `window.displayedAnchor` if it named this modal.
  - `window.showModalItem(itemAnchor)` — takes a String element id, returns nothing. No-ops if no element has that id. Sets `display: inline`, sets `window.displayedAnchor`, and if the modal contains a `<video>`, lazily assigns `src` from `data-video-url` and plays it.
  - `window.displayedAnchor` — String id of the open modal, or `null` when none is open. Previously it was only ever set, never cleared; from this task forward `null` is a valid, meaningful value.

- [ ] **Step 1: Replace the two cancel-click functions with `hideModalItem` + `onModalCancelClick`**

Replace lines 105–117 in `public/js/application.js` — that is, both `window.onModalCancelClick` and `window.onVideoModelCancelClick` — with the following. Remember the space-tab indentation on the lines being replaced.

```js
  window.hideModalItem = function (modalDiv) {
    var video = $(modalDiv).find('video').get(0);
    if (video != null) {
      video.pause();
      video.load();
    }
    modalDiv.style.display = 'none';
    if (window.displayedAnchor == modalDiv.id) {
      window.displayedAnchor = null;
    }
  }

  window.onModalCancelClick = function (modalDiv) {
    hideModalItem(modalDiv);
    var pathParts = anchorParts(window.location.hash);
    history.pushState(null, null, anchor(pathParts["section"], null));
    onScroll();
  }

  window.onVideoModelCancelClick = function (modalDiv) {
    onModalCancelClick(modalDiv);
  }
```

Three notes on this block:

- The parameter is renamed `modelDiv` → `modalDiv` (the original was a typo). Rename it consistently within these functions only; do not go renaming it elsewhere in the file.
- `video.load()` is what rewinds to 0:00. It is required, not incidental — see Global Constraints.
- `onVideoModelCancelClick` is temporarily reduced to a pass-through rather than deleted. Templates still call it, and this task must not break them. Task 4 deletes it along with its callers.

- [ ] **Step 2: Make `showModalItem` video-aware**

Replace lines 173–176, currently:

```js
  window.showModalItem = function (itemAnchor) {
    document.getElementById(itemAnchor).style.display = 'inline';
    window.displayedAnchor = itemAnchor;
  }
```

with:

```js
  window.showModalItem = function (itemAnchor) {
    var modalDiv = document.getElementById(itemAnchor);
    if (modalDiv == null) { return; }
    modalDiv.style.display = 'inline';
    window.displayedAnchor = itemAnchor;
    var video = $(modalDiv).find('video').get(0);
    if (video != null) {
      var source = $(modalDiv).find('source').get(0);
      var videoUrl = source.getAttribute("data-video-url");
      if (source.getAttribute("src") != videoUrl) {
        source.setAttribute("src", videoUrl);
        video.load();
      }
      video.play().catch(function () {});
    }
  }
```

Why each guard is there — do not remove them as redundant:

- `if (modalDiv == null) { return; }` — the existing `hashchange` handler can reach here with `itemAnchor` of `null`, where `getElementById(null)` returns `null` and the next line throws `TypeError`. This is a live bug today.
- `if (source.getAttribute("src") != videoUrl)` — gallery videos ship with `src` unset so the browser does not download them until first open. Re-setting `src` on reopen would restart the download. `equil.erb` and `amphibians.erb` ship with `src` already set, so they take the skip branch on first open too, which is correct.
- `.catch(function () {})` — `play()` returns a Promise that genuinely rejects in two cases here: deep-linking to a video URL calls `play()` with no user gesture and autoplay policy blocks it, and a `load()` racing a pending `play()` rejects with "interrupted by a new load request". Both currently produce unhandled-rejection noise in the console. Swallowing them changes no behavior.

- [ ] **Step 3: Verify the file still parses**

Run: `node --check public/js/application.js`

Expected: no output, exit status 0. A syntax error here means the edit clipped a brace.

If `node` is unavailable, load `http://localhost:3000/` in a browser after starting the server and confirm no `SyntaxError` appears in the console. The page's menu opening at all is sufficient proof the file parsed.

- [ ] **Step 4: Confirm nothing server-side regressed**

Run: `bundle exec rake test`

Expected: PASS, same count as before your change. These tests do not exercise the JS; this is a guard against having accidentally edited a Ruby file or broken static asset serving.

- [ ] **Step 5: Commit**

```bash
git add public/js/application.js
git commit -m "refactor: add video-aware hideModalItem and showModalItem primitives"
```

---

### Task 2: Route arrow-key navigation through `hideModalItem`

Fixes the arrow-key leak and the `ReferenceError` in the keydown guard. Two small, independent edits in the same neighborhood.

**Files:**
- Modify: `public/js/application.js:156-160` (`showNextModalItem`)
- Modify: `public/js/application.js:162-171` (`showNextModalItemViaKeydown`)

**Interfaces:**
- Consumes: `window.hideModalItem(modalDiv)` and the `window.displayedAnchor == null` convention from Task 1.
- Produces: nothing new. Signatures of both functions are unchanged.

- [ ] **Step 1: Pause the outgoing item in `showNextModalItem`**

In `showNextModalItem`, replace this line:

```js
    document.getElementById(currentItemAnchor).style.display = 'none';
```

with:

```js
    hideModalItem(document.getElementById(currentItemAnchor));
```

Leave the rest of the function untouched.

- [ ] **Step 2: Fix the keydown guard**

In `showNextModalItemViaKeydown`, replace this line:

```js
    if (displayedAnchor in window) {
```

with:

```js
    if (window.displayedAnchor != null) {
```

The original tests a bare, undeclared identifier — on a page where no modal has ever been opened, evaluating `displayedAnchor` throws `ReferenceError` rather than yielding false. The new form also correctly reports "nothing open" now that Task 1 nulls the value on hide.

- [ ] **Step 3: Verify the file still parses**

Run: `node --check public/js/application.js`

Expected: no output, exit status 0.

- [ ] **Step 4: Spot-check in the browser**

Start the server: `bundle exec puma -C config/puma.rb` (leave it running for subsequent tasks). It serves on port 3000 unless `PORT` is set. Note this is the same command the `Procfile` uses — `rackup` is *not* available in this project, since Rack 3 moved it to a separate gem that is not in the bundle.

Open `http://localhost:3000/`, scroll to the videos section, open a video, then press the right arrow key. Expected: the next item appears and **the first video's audio stops**. Before this task it kept playing.

Then reload the page and, without opening anything, press the left arrow key. Expected: no `ReferenceError` in the console.

- [ ] **Step 5: Commit**

```bash
git add public/js/application.js
git commit -m "fix: pause the outgoing video during arrow-key modal navigation"
```

---

### Task 3: Unify the history handlers

This is the task that fixes the reported bug. `popstate` and `hashchange` both fire on a fragment-only Back, so rather than maintaining two handlers that must agree, both bind to one idempotent function.

**Files:**
- Modify: `public/js/application.js:192-198` (the `hashchange` handler — delete it)
- Modify: `public/js/application.js:283-293` (the `popstate` handler — replace it)

**Interfaces:**
- Consumes: `window.hideModalItem(modalDiv)` and `window.showModalItem(itemAnchor)` from Task 1; `window.anchorParts(locationHash)` which already exists and returns `{section, item}` with `null` for absent parts.
- Produces: `window.syncModalsToHash()` — takes nothing, returns nothing. Reads `window.location.hash` and brings every modal's visibility into agreement with it. Safe to call repeatedly; calling it twice in a row is a no-op the second time.

- [ ] **Step 1: Delete the `hashchange` handler**

Remove this block entirely (lines 192–198):

```js
  $(window).on('hashchange', function() {
    if (displayedAnchor in window) {
      var pathParts = anchorParts(window.location.hash);
      document.getElementById(window.displayedAnchor).style.display = 'none';
      window.showModalItem(pathParts.item);
    }
  });
```

It is replaced wholesale in Step 2. It is not worth repairing in place: it contains the same bare-`displayedAnchor` `ReferenceError` as the keydown guard, and when `displayedAnchor` *is* set it calls `showModalItem(null)` on a Back-to-section, which throws.

- [ ] **Step 2: Replace the `popstate` handler with `syncModalsToHash`**

Replace this block (lines 283–293):

```js
  $(window).bind('popstate', function(e) {
    var pathParts = anchorParts(window.location.hash);
    if (pathParts['item'] == null) {
      $('.wrapper, .equiwrapper, .amphiwrapper, .bodywrapper').find('.w3-modal').each(function(index, modalDiv) {
        modalDiv.style.display = 'none';
      });
    }
    else {
      window.showModalItem(pathParts["item"]);  
    }
  });
```

with:

```js
  window.syncModalsToHash = function () {
    var pathParts = anchorParts(window.location.hash);
    $('.wrapper, .equiwrapper, .amphiwrapper, .bodywrapper').find('.w3-modal').each(function (index, modalDiv) {
      if (modalDiv.id != pathParts["item"]) {
        hideModalItem(modalDiv);
      }
    });
    if (pathParts["item"] != null) {
      showModalItem(pathParts["item"]);
    }
  }

  $(window).bind('popstate', window.syncModalsToHash);
  $(window).on('hashchange', window.syncModalsToHash);
```

Two details that matter:

- **Hide-everything-except-the-target, then show the target.** The old handler had two mutually exclusive branches, and the `else` branch never hid the previously-open modal. Unconditional hide-all-but-target covers both cases in one pass.
- **The `modalDiv.id != pathParts["item"]` guard is load-bearing.** Without it, navigating *to* a video modal would hide it (calling `pause()` and `load()`) microseconds before showing it, restarting the download and fighting the `play()`. The guard is what makes the double-fire harmless: the second invocation finds the target already shown, `src` already matching, and calls `play()` on an already-playing video, which is a no-op.

- [ ] **Step 3: Verify the file still parses**

Run: `node --check public/js/application.js`

Expected: no output, exit status 0.

- [ ] **Step 4: Verify the reported bug is fixed**

With the server running, open `http://localhost:3000/`, scroll to the videos section, open a video, let audio start, then press the browser Back button.

Expected: the modal hides **and the audio stops**. This is the bug from the original report.

Then press Forward. Expected: the video modal reopens **and plays** — the inverse bug, also fixed by this task.

Check the console during both. Expected: no `TypeError` or `ReferenceError`.

- [ ] **Step 5: Commit**

```bash
git add public/js/application.js
git commit -m "fix: stop video playback when navigating away via browser history"
```

---

### Task 4: Delete the video-specific variants

With `showModalItem` and `onModalCancelClick` now video-aware, the three video-specific functions are redundant. Deleting the functions and updating their fourteen call sites happens in **one commit** so no template ever references a function that does not exist.

**Files:**
- Modify: `public/js/application.js` (delete `onVideoModelCancelClick`, `onVideoThumbnailClick`, `showModalVideoItem`; simplify the boot branch)
- Modify: `app/views/_videos.erb:9,10` (2 call sites)
- Modify: `app/views/equil.erb:10,12,25,26,27,40,41,42` (9 call sites — note line 10 contains **two**)
- Modify: `app/views/amphibians.erb:33,34,36` (3 call sites)

**Interfaces:**
- Consumes: `window.showModalItem`, `window.onModalCancelClick`, `window.onThumbnailClick` — all already video-aware after Tasks 1–3.
- Produces: nothing new. This task only removes.

- [ ] **Step 1: Update the fourteen template call sites**

The replacement is mechanical and argument lists are unchanged, including the `null` section argument the standalone installation pages pass:

- `onVideoThumbnailClick(` → `onThumbnailClick(`
- `onVideoModelCancelClick(` → `onModalCancelClick(`

Apply across exactly three files:

```bash
sed -i 's/onVideoThumbnailClick(/onThumbnailClick(/g; s/onVideoModelCancelClick(/onModalCancelClick(/g' \
  app/views/_videos.erb app/views/equil.erb app/views/amphibians.erb
```

- [ ] **Step 2: Verify every call site was converted**

Run:

```bash
grep -rn 'onVideoThumbnailClick\|onVideoModelCancelClick\|showModalVideoItem' app/views/
```

Expected: **no output**. Any remaining hit is a call site that will throw "function is not defined" at runtime once Step 3 lands.

Then confirm the replacements landed where expected:

```bash
for f in app/views/_videos.erb app/views/equil.erb app/views/amphibians.erb; do
  echo "$f: $(grep -o 'onThumbnailClick\|onModalCancelClick' $f | wc -l)"
done
```

Expected: `_videos.erb: 2`, `equil.erb: 9`, `amphibians.erb: 3`. If a count is short, a call site was missed.

- [ ] **Step 3: Delete the three functions**

In `public/js/application.js`, delete these three blocks in full:

```js
  window.onVideoModelCancelClick = function (modalDiv) {
    onModalCancelClick(modalDiv);
  }
```

```js
  window.onVideoThumbnailClick = function (section, itemAnchor) {
    history.pushState(null, null, anchor(section, itemAnchor));
    showModalVideoItem(itemAnchor);
  }
```

```js
  window.showModalVideoItem = function (itemAnchor) {
    var modelDiv = document.getElementById(itemAnchor);
    var source = $(modelDiv).find('source').get(0);
    var videoUrl = source.getAttribute("data-video-url");
    var video = $(modelDiv).find('video').get(0);
    if (source.getAttribute("src") != videoUrl) {
      video.pause();
      source.setAttribute("src", videoUrl);
      video.load();
    }
    showModalItem(itemAnchor);
    video.play();
  }
```

- [ ] **Step 4: Simplify the boot-time branch**

In the "open modals if their id is in the url" block, replace:

```js
        if (pathParts["section"] == "videos") {
          window.showModalVideoItem(pathParts["item"]);
        }
        else {
          window.showModalItem(pathParts["item"]);
        }
```

with:

```js
        window.showModalItem(pathParts["item"]);
```

Keep the surrounding `$(window).scrollTop(...)` and `history.pushState(...)` lines as they are.

- [ ] **Step 5: Verify no dangling references anywhere**

Run:

```bash
grep -rn 'onVideoThumbnailClick\|onVideoModelCancelClick\|showModalVideoItem' app/ public/js/application.js
```

Expected: **no output**.

Run: `node --check public/js/application.js`

Expected: no output, exit status 0.

- [ ] **Step 6: Confirm nothing server-side regressed**

Run: `bundle exec rake test`

Expected: PASS. ERB templates are rendered by the route tests, so a template mangled by the `sed` in Step 1 would surface here as a render error.

- [ ] **Step 7: Commit**

```bash
git add public/js/application.js app/views/_videos.erb app/views/equil.erb app/views/amphibians.erb
git commit -m "refactor: fold the video-specific modal functions into the general ones"
```

---

### Task 5: Manual verification pass

The full checklist from the spec, run once against the finished change. This is the only verification this change gets — there is no automated coverage of any of it, so do not skip steps on the assumption that an earlier task already proved them.

**Files:** none modified.

**Interfaces:** none.

- [ ] **Step 1: Start the server**

Run: `bundle exec puma -C config/puma.rb`

Open `http://localhost:3000/` with the browser console visible. Keep it visible for every step below — several checks are "no error appears".

- [ ] **Step 2: Work the checklist**

Record a pass/fail for each. Steps 6 and 8 are the blast-radius checks; steps 5 and 7 confirm the pre-existing console errors documented in the spec are gone.

1. Open a gallery video, press Back — audio stops and the modal hides.
2. Open a gallery video, click the `X` — audio stops. *(Regression check on the path that already worked.)*
3. Open a gallery video, press the left or right arrow key — the first video's audio stops as the next item appears.
4. Open a gallery video, press Back, then Forward — the video reopens **and plays**.
5. Deep-link to `/#/s/videos/i/<anchor>` using a real anchor from the page — the modal opens, and blocked autoplay produces **no unhandled rejection** in the console.
6. Open an image modal on `/metapolis` or `/bodyscapes`, press Back — it still closes normally.
7. Load a page fresh and press an arrow key before opening anything — **no `ReferenceError`** in the console.
8. Repeat step 1 on `/equil` and on `/amphibians` — audio stops there too.

- [ ] **Step 3: Reopen a video and confirm it restarts**

Open a gallery video, let it play a few seconds, close it with the `X`, then reopen it.

Expected: playback starts from 0:00, not from where you left off. This confirms the `video.load()` in `hideModalItem` still does its job.

- [ ] **Step 4: Report results**

Report the outcome of all eight checks plus Step 3 honestly, including any that failed. Do not describe the change as verified if any step failed or was skipped — say which, and why.

If everything passed, there is nothing to commit for this task; the work is already committed across Tasks 1–4.

---

## Notes for the reviewer

**Why the tasks are ordered this way.** Each commit leaves the app working. Task 1 adds the new primitives while the old video-specific functions still exist and still work, so templates are never broken. Task 4 deletes those functions and updates their callers in a single commit, so there is no intermediate state where a template calls a function that has been removed.

**Deliberate redundancy in Task 1.** `onVideoModelCancelClick` is reduced to a pass-through rather than deleted, and briefly the close path pauses an already-paused video. That is intentional and temporary — it is what keeps Task 1's commit independently working.

**One incidental fix worth knowing about.** The block at the end of the boot sequence that opens modals on the `equiwrapper`/`amphiwrapper`/`bodywrapper` pages already calls `showModalItem`. Because Task 1 makes that function video-aware, deep-linking to an `equil` or `amphibians` video now plays it, where previously the modal opened silent. No task changes that line; it falls out of the primitive change. Do not be surprised by it during Task 5.

**The riskiest step is Task 4 Step 1.** Fourteen template edits with no automated coverage. A missed call site fails silently at runtime — the `onclick` references an undefined function and that modal simply stops responding to clicks. Task 4 Step 2's grep and counts are the guard; Task 5 checks 2 and 8 exercise every edited file.
