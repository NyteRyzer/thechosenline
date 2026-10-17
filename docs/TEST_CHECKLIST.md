# Manual Test Checklist — v0.2.0

Run the automated suite first:
`godot --headless --path . res://tests/test_runner.tscn` (exit code 0 means everything passed).
Then play through this list on each desktop OS before tagging a build.

## Launch and title
- [ ] The game launches to the title screen with no errors in the console (`[ContentDB] ... (0 errors, 0 warnings)`).
- [ ] With no saves, **Continue** is disabled and **New Game** has focus.
- [ ] Every title button can be reached with the arrow keys and Tab and activated with Enter.
- [ ] **Settings** opens and closes with Esc and with Back. Focus returns to the Settings button.
- [ ] **Quit** exits.

## Interaction (living room)
- [ ] New Game plays the intro. Clicking anywhere, Enter or Space advances; Esc or Skip ends it.
- [ ] After the intro, a hotspot has keyboard focus (orange corner brackets).
- [ ] Tab and the arrow keys move between all 8 hotspots. Holding **H** labels them all.
- [ ] Every hotspot shows dialogue or changes room. A tick appears after examining it.
- [ ] Hovering a hotspot shows its name at the bottom of the screen.
- [ ] **Window** gives the Glass Shard and the evidence *Glass Fell Outward* (with toasts). Examining it again gives a different line and no duplicate item.
- [ ] **Key Hooks** gives the Brass Key Tag and *The Spare Key Is Gone*.
- [ ] **Front Door** gives *The Front Lock Wasn't Forced* on the first visit.
- [ ] **Under the Couch** without the flashlight says it is too dark.

## Room transition (kitchen)
- [ ] The **Kitchen** doorway fades to the kitchen and plays the kitchen intro once only.
- [ ] **Junk Drawer** gives the Flashlight.
- [ ] **Back Door** and **Muddy Footprints** add evidence.
- [ ] The **Living Room** doorway returns, and the intro does not replay.

## Item use
- [ ] I opens the inventory. Choose Flashlight and the HUD shows "Using: Flashlight...".
- [ ] Hovering a hotspot shows "Use Flashlight on ...".
- [ ] Right-click or Esc cancels the selection without opening the menu.
- [ ] Using the Flashlight on **Under the Couch** reveals the Pale Gold Feather and its evidence.
- [ ] Using an item on the wrong object gives a "won't help" line.
- [ ] With all three clues, **Front Door** points to the Deduction Board. The Journal objective changes.

## Deduction and chapter ending
- [ ] B (or the Journal button) opens the Deduction Board, and Esc or B closes it.
- [ ] A wrong answer shows its rebuttal and plays the "wrong" tone. Missing or unrelated evidence shows a hint.
- [ ] "They used our spare key..." plus Glass, Spare Key and Front Lock solves it and plays the success dialogue.
- [ ] The front door then ends Chapter 1: the bell rings and the recap shows the evidence found and playtime.
- [ ] Keep Exploring returns to the room. Return to Title works. Continue then resumes after the chapter.

## Audio
- [ ] Title music plays on the title screen and fades out when the game starts.
- [ ] The living room and kitchen ambience crossfade on room change, and the clock ticks in the kitchen.
- [ ] Pickup, evidence, door, bell and deduction sounds play. Each volume slider affects its category.

## Builds
- [ ] Windows: the unzipped `.exe` launches (after SmartScreen's "Run anyway").
- [ ] macOS: the app opens via right-click → Open, on both Apple Silicon and Intel.
- [ ] Linux: `./TheChosenLine.x86_64` launches.
- [ ] On each OS, saves and settings persist between launches.

## Journal and inventory
- [ ] J and I open and close their panels. Esc closes them too.
- [ ] Focus never escapes to hotspots behind an open panel (Tab cycles inside the panel only).
- [ ] Evidence cards show their title and text; the objective line is present.

## Save and load
- [ ] Esc then **Save Game** saves to Slot 1. The slot shows the room, chapter, playtime and date.
- [ ] Saving to a used slot asks "Overwrite?" first.
- [ ] Change state (pick something up), then **Load Game** and Slot 1 restores the earlier state exactly (inventory, journal, ticks, room).
- [ ] The autosave slot updates on every room change.
- [ ] Quit to Title, then **Continue** loads the newest save.
- [ ] Deleting a slot file by hand, or corrupting it, shows "Damaged save" or "Empty" and does not crash.

## Settings and accessibility
- [ ] Text size (Small to Extra Large) resizes all UI text immediately.
- [ ] High contrast switches to black panels, white borders and yellow focus.
- [ ] *Always highlight objects* keeps hotspot labels visible.
- [ ] Volume sliders move in steps of 5% and work with the arrow keys.
- [ ] Settings persist after restarting the game.

## Debug
- [ ] F3 toggles the overlay. Room, flags, inventory and evidence IDs update live.
