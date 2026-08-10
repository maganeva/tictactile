# Pausing videos on every modal-close path

## Problem

Closing a video modal with the `X` icon stops playback. Navigating away with the
browser's Back button hides the modal but leaves the video playing, so the user
keeps hearing audio from a video they can no longer see.

The `X` path is the only one that knows videos exist:

```js
window.onVideoModelCancelClick = function (modelDiv) {
  var video = $(modelDiv).find('video').get(0);
  video.pause();
  video.load();
  onModalCancelClick(modelDiv);
}
```

Every other path hides the modal with a bare `modalDiv.style.display = 'none'`.
There are four such paths in `public/js/application.js`:

| Path | Location | Symptom |
| --- | --- | --- |
| Back button | `popstate` handler, `:283` | audio continues (reported bug) |
| Arrow-key navigation | `showNextModalItem`, `:157` | audio continues under the next item |
| Hash change | `hashchange` handler, `:195` | audio continues |
| Forward button into a video | `popstate` else-branch, `:291` | inverse bug: modal opens, video never plays |

The leak is not specific to the gallery. `app/views/equil.erb` and
`app/views/amphibians.erb` use the same modal functions and fail identically.

### Two complications found while mapping the paths

**`popstate` and `hashchange` both fire** when history traversal changes only the
fragment. The Back button therefore runs both handlers today, not one. Any fix
must decide which handler owns the transition or make the transition idempotent.

**The `hashchange` handler is already broken.** Lines 163 and 193 test a bare
identifier:

```js
if (displayedAnchor in window) {
```

`displayedAnchor` is unquoted, so on a page where no modal has been opened the
identifier is undeclared and this throws `ReferenceError` instead of evaluating
false. When it *is* set, `window.displayedAnchor` is never cleared on close, so
after a Back-to-section the handler falls through to `showModalItem(null)` and
`document.getElementById(null).style.display` throws `TypeError`.

This was determined by reading the code, not by observing the console. It is
listed in the verification checklist below for confirmation.

## Approach

Replace the scattered `display` assignments with one symmetric pair of
functions that are video-aware, and route all four paths through them. The
video-specific function variants are deleted rather than kept alongside, so
there is exactly one way to open a modal and one way to close it.

Two alternatives were considered and rejected:

- **Call `pauseAllVideos()` at the top of each handler.** Blunt and low-risk,
  but it does not fix the forward-navigation case (a missing `play()`, not a
  stray `pause()`), and it leaves the show/hide duplication in place so the next
  path added leaks again.
- **Derive all modal state from the URL (`renderFromHash()`).** Dissolves the
  double-fire problem completely, but page boot also handles scroll positioning
  and the menu sidebar, so it cannot collapse into the same entry point. That
  pays most of the refactor cost without yielding a single code path.

## Design

### Primitives

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

`video.load()` in `hideModalItem` resets playback to 0:00, preserving the
behavior of today's `X` button. Because `src` remains set, the reopen path finds
`src` already equal to `data-video-url`, skips the redundant `load()`, and
`play()` starts from the beginning. The gallery's lazy-src behavior — `src`
unset in markup until first open — is preserved by the same comparison.

The `.catch()` handles two rejections that are unhandled today: `play()` called
without a user gesture when deep-linking to a video URL, which autoplay policy
blocks; and `load()` racing a pending `play()`, which rejects with "interrupted
by a new load request". Both are logged errors only; swallowing them does not
change behavior.

Clearing `window.displayedAnchor` is what makes the keydown guard reflect
reality instead of naming a closed modal.

### History handlers

`popstate` and `hashchange` bind to one idempotent function:

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

Hide everything except the target, then show the target. Running it twice is a
no-op, so the double-fire stops mattering rather than needing to be suppressed.
The `modalDiv.id != pathParts["item"]` guard prevents hiding and immediately
re-showing the modal being navigated to, which would reload its video.

This replaces the existing `hashchange` handler at `:192` entirely, removing the
broken `displayedAnchor` test along with it.

### Remaining call sites

- `showNextModalItem` (`:157`): replace
  `document.getElementById(currentItemAnchor).style.display = 'none'` with
  `hideModalItem(document.getElementById(currentItemAnchor))`.
- `showNextModalItemViaKeydown` (`:163`): replace `if (displayedAnchor in window)`
  with `if (window.displayedAnchor != null)`.

### Deleted functions

`showModalVideoItem`, `onVideoModelCancelClick`, and `onVideoThumbnailClick` are
removed. Their general counterparts — `showModalItem`, `onModalCancelClick`,
`onThumbnailClick` — are now video-aware and cover both cases.

`onModalCancelClick` delegates its hide to the new primitive:

```js
window.onModalCancelClick = function (modalDiv) {
  hideModalItem(modalDiv);
  var pathParts = anchorParts(window.location.hash);
  history.pushState(null, null, anchor(pathParts["section"], null));
  onScroll();
}
```

The boot-time branch at `:232` that chooses `showModalVideoItem` for the
`videos` section collapses to an unconditional `showModalItem`.

### Template updates

Call sites of the deleted functions, all mechanical replacements:

| File | Call sites |
| --- | --- |
| `app/views/_videos.erb` | 2 |
| `app/views/equil.erb` | 9 |
| `app/views/amphibians.erb` | 3 |

`onVideoThumbnailClick` becomes `onThumbnailClick`; `onVideoModelCancelClick`
becomes `onModalCancelClick`. Argument lists are unchanged, including the
`null` section argument passed on the standalone installation pages.

Keeping the old names as aliases was considered and rejected: it avoids the
template churn but leaves three functions whose only purpose is to be an
obsolete name, which reintroduces the "two ways to do it" condition that caused
this bug.

## Verification

Verification for this change is manual.

This project has no JavaScript test harness — the suite is minitest and
rack-test, and cannot observe `video.paused`. The existing smoke tests verify
the deployable artifact and are not the place for regression coverage of
front-end behavior; if regression tests for this are wanted later, they belong
in a separate mechanism introduced for that purpose. Standing up such a harness
is out of scope here: it is a larger change than the fix and would hold the
audio bug behind a test-infrastructure project.

### Manual checklist

1. Open a gallery video, press Back — audio stops and the modal hides.
2. Open a gallery video, click `X` — audio stops (regression check on the path
   that already worked).
3. Open a gallery video, press the left or right arrow key — the first video's
   audio stops as the next item appears.
4. Open a gallery video, press Back, then Forward — the video reopens *and*
   plays.
5. Deep-link to `/#/s/videos/i/<anchor>` — the modal opens, and blocked autoplay
   produces no unhandled rejection in the console.
6. Open an image modal on `metapolis` or `bodyscapes`, press Back — it still
   closes normally.
7. Load a page fresh and press an arrow key before opening anything — no
   `ReferenceError` in the console.
8. Repeat step 1 for the `equil` and `amphibians` videos.

Steps 5 and 7 also confirm the pre-existing console errors described above.

### Risk note

Because the fourteen template edits are unverified by any automated check, a
missed call site fails silently at runtime — the `onclick` handler references an
undefined function and the modal stops responding. Step 2 of the checklist
covers the gallery and step 8 covers `equil` and `amphibians`, which together
exercise every edited file.
