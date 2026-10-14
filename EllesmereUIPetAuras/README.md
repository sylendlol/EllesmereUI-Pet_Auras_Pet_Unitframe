# EllesmereUI Pet Auras

Your pet's buffs and debuffs, right next to your pet frame.

**EllesmereUI Pet Auras** is a small add-on for [EllesmereUI](https://www.curseforge.com/wow/addons/ellesmereui) that shows your pet's buffs and debuffs next to the pet frame. You set it up inside the EllesmereUI options panel, under **Dworak > Pet Auras**, with a live preview at the top of the page.

It works with EllesmereUI's own pet frame and with the pet frames of other unit frame add-ons (Blizzard default, ElvUI, Shadowed Unit Frames and others).

---

## Features

### Two separate blocks
- Buffs and debuffs are placed **independently**: for example, buffs above the pet frame and debuffs below it.
- Each block has its own **position** (above / below the pet frame), **growth direction** (left to right or right to left) and **X / Y offset**.

### Icons
- Icon size, spacing, icons per row and max icons for each block.
- Adjustable border thickness. **Debuff borders show the dispel type color** (Magic, Curse, Poison, Disease).
- **Sort order:** Applied Order (a new aura goes to the end of the row), Remaining Time, Name or Blizzard Default, optionally reversed.
- Filters: **Only My Buffs** and **Only Dispellable Debuffs**.

### Timer and stack text
- Show or hide the remaining time.
- **Font** (every EllesmereUI font plus SharedMedia fonts), **size** and **outline** (EUI Global Default, Drop Shadow, Outline, Thick Outline).
- **Timer position** on the icon: top, center or bottom, fine-tuned with X / Y.
- Stack count size.

### Live preview
The top of the settings page shows a copy of your pet frame (same size, same health bar color, your pet's name) with placeholder buffs and debuffs. Every change shows up immediately: position, growth, icon size, spacing, rows, border, dispel colors, sort order, timer font, size, outline and position, and stack text.

### Move Auras
Shows placeholder auras on your **real pet frame**. Drag the colored blocks into place; right-click a block to reset its offset. It works even when your pet is not out.

### Any pet frame
- **Anchor To** lists every pet frame the add-on finds: EllesmereUI, Blizzard default, ElvUI, Shadowed Unit Frames, PitBull, Z-Perl and any other frame that shows your pet.
- **Pick Frame:** hover any frame on screen and left-click it.
- **None (Free Position):** place the auras anywhere on the screen.

### Profiles, import and export
- Settings are saved in the **EllesmereUI profile**, so they switch with your EllesmereUI profiles and travel in EllesmereUI profile exports.
- A separate **Export / Import** string on the page carries just the Pet Auras settings.

---

## Performance

Pet Auras uses Blizzard's own aura system (AuraContainer). **The game client tracks and draws the auras itself**, in combat and with secret auras too.

- The add-on **never reads aura data** and runs **no Lua code** when an aura changes, so it costs no CPU in combat.
- **No taint**: auras update correctly in combat, and expired auras disappear right away.
- Layout changes are applied outside of combat; a change made in combat is applied when combat ends.

---

## Requirements

- **EllesmereUI** (with its Unit Frames module, if you want to use the EllesmereUI pet frame)
- **EllesmereUIDworak** (the "Dworak" section of the EllesmereUI panel)
- A client with the AuraContainer system (Retail 12.x, WoW Forever)

## Installation

1. Download the latest release.
2. Copy the `EllesmereUIPetAuras` folder into `World of Warcraft\<client>\Interface\AddOns\`.
3. Restart the game (a new add-on folder is not picked up by `/reload`).
4. Open the EllesmereUI panel and go to **Dworak > Pet Auras**, or type `/pa`.

### Upgrading from the standalone "EllesmereUI Pet Auras" (EllesmereUI_PetAuras)
Your old settings are taken over automatically on the first login. After that you can delete the old `EllesmereUI_PetAuras` folder. Old export strings (`EUIPA1:`) can be imported too.

---

## Commands

| Command | What it does |
|---|---|
| `/pa` or `/petauras` | Opens the settings page |
| `/pa move` | Turns Move Auras on / off |
| `/pa pick` | Pick the pet frame with the mouse |
| `/pa reset` | Restores the default settings |

---

## FAQ

**I see every aura twice.**
EllesmereUI 9.5.4 and later also has its own optional pet buff/debuff display (Unit Frames > Pet). Use only one of the two.

**The auras do not show up.**
Check **Anchor To** on the settings page. If the add-on did not find your pet frame, pick it from the list or use **Pick Frame**.

**Can I move the auras in combat?**
No. Move Auras and layout changes need you to be out of combat; Move Auras switches off when combat starts.

---

## Author

Dworak
