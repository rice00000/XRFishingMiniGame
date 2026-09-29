# River Harpoon

A small, data-driven harpoon game for low-vision research. The player stands on the shore, aims a large high-contrast ring at floating objects and presses one button to spear one of them. **One experiment is one `.tres` file** in `experiments/`, and the game lists that folder in a menu you can use from inside the headset.

```
river/
  experiments/       one file per experiment; the in-game menu lists this folder
  scripts/           gameplay (experiment, rules, spawner, harpoon, menu, logger, ...)
  scripts/input/     AimInput + XR and PC/Mac implementations
  scripts/skin/      RiverSkin, Scenery, SkinModel (visual-only layer)
  skins/lagoon/      the lagoon look: scenery, water/sand shaders, model wrappers
  art/               downloaded CC0 models, character pictures, sky (see art/CREDITS.md)
  tools/             reference_image_maker (renders PNGs of objects)
```

## Playing on PC, Mac or VR
Press **F5** and the experiment menu appears. Aim at an experiment and fire to start it. The `<` `>` buttons set the participant number, which goes into every log and is remembered between app starts. The menu button stops a run (logged as `aborted`) and goes back to the menu. After the last trial the menu comes back by itself.

| Where | Aim | Fire | Menu |
|---|---|---|---|
| VR headset (Quest, SteamVR) | right controller (`XRAimRight`, aim pose) | trigger | left controller menu button |
| PC / Mac | mouse, **or** arrow keys / WASD, **or** gamepad left stick | left click, Space, Enter, gamepad A | Esc, gamepad Start |

Remap the PC/Mac keys in **Project Settings > Input Map** (`harpoon_fire`, `harpoon_aim_*`, `harpoon_menu`). If those actions are missing, default bindings are added at runtime.

To skip the menu (scripts, quick tests), pass arguments after `--`: `godot --path . -- --experiment=fastest_of_five_identical_fish --participant=12` (the file name without its number).

To support another device, write a script that `extends AimInput`, implement `get_aim_ray()` and emit `confirm_pressed` (and `back_pressed` for the menu), then assign the node to **RiverGame > Input > Input Override**.

## Writing an experiment
**Quickest start:** in the FileSystem dock, right-click `experiments/` > **New Resource...** > `Experiment`, name it and save. A new experiment already contains one task with five identical fish at five speeds, and the lagoon look, so it runs as it is. Change what you need. You can also duplicate an existing file and edit it. Everything the experiment needs is in that one file, and the menu picks it up automatically.

**The file name is the experiment's name.** The menu shows it with spaces (`01_fastest_of_five_identical_fish.tres` → "01 Fastest of five identical fish"), so name a file for what it tests, in a few words. The number sets the menu order and is left out of the name used in logs (`fastest_of_five_identical_fish`). Very long names get a smaller font in the menu.

There are two levels: an **Experiment** has **tasks**, and a task has **objects**. `01_fastest_of_five_identical_fish.tres` as the Inspector shows it:

```
Experiment   description          "Five identical fish swim at 0.15 to 0.75 m/s. ..."
             tasks                [1]
               question_text      "Catch the fish that swims the FASTEST!"
               correct_answer_rule  fastest moving
               objects_in_trial   [1]
                 name             fish
                 shape            capsule   color  orange   size  0.6
                 variable         swim_speed_m_per_s
                 variable_values  0.15, 0.3, 0.45, 0.6, 0.75
               repeat_times       3
             look                 lagoon
```

Each Inspector section is ordered from common to rare; hover a field for its explanation.

| | Main fields | Folded groups |
|---|---|---|
| **Experiment** | `description`, `tasks`, `shuffle_trial_order`, `look` | Feedback (texts, timings), Advanced (`reward_table`, `fixed_seed`) |
| **Task** | `question_text`, `correct_answer_rule`, `correct_tag`, `objects_in_trial`, `objects_per_trial` (0 = all), `repeat_times` | Reference (`reference_object`, `each_object_as_reference`, `show_reference_model`, `reference_image`), Trial (`time_limit`, `retry_until_correct`), Advanced (`name`, `extra_pools`, `custom_rule`, `fixed_layout_seed`) |
| **Object** | `name`, `tags` | Look (`shape`, `color`, `size`, `scene`, `picture`, `show_spin_marker`), Default motion (`swim_speed_m_per_s`, `spin_speed_deg_per_s`, `float_height`), Independent variable (`variable`, `variable_values`), Spin direction (`spin_axis`, `start_tilt_degrees`), Model import fixes, Selection (`selection_radius_m`) |

`correct_answer_rule` is one of: **fastest moving**, **slowest moving**, **fastest spinning**, **slowest spinning**, **same as reference** (the task's reference object), **has tag** (objects with `correct_tag`), **custom** (`custom_rule`).

Three settings remove most of the copying:
- **Object `variable` + `variable_values`**: one object, many values of one number. With `variable = swim_speed_m_per_s` and `variable_values = 0.15, 0.3, ...` you get `fish_0.15`, `fish_0.3`, and so on. Use it for the independent variable; the names in the logs show the level. The values replace that property's default, so use its unit (m/s, degrees/s, metres); `spin_speed_deg_per_s = 55` with values of 0.15 to 0.75 spins at 0.15 to 0.75 degrees/s.
- **Task `repeat_times`**: how many times the task runs. Turn on the experiment's `shuffle_trial_order` to mix the trials of all tasks.
- **Task `each_object_as_reference`**: one trial per object, each with that object as the reference and its `picture` on the panel ("find this one", for every character).

**More complex setups** stay in the same file. `objects_per_trial` picks a random subset of the objects each trial. `extra_pools` (Task > Advanced) adds more groups with their own counts, e.g. one fixed target plus 3 random distractors; see `same_as_this` in `90_demo_of_six_task_types.tres`. `custom_rule` takes any script that extends `TaskRule`.

A `name` is only a label that shows in the logs, and rewards and skin exceptions can match it. Leave it empty and an object is named after its shape (`capsule`, `capsule_2`, ...) and a task is called `task1`, `task2`, ... by position. Give objects a name when you want readable logs or need to tell them apart. The menu shows each experiment's description and trial count, and shows setup problems (two objects with the same name, a task without objects, ...) in orange.

## Looks (visual only): stimuli vs. decoration
- A **stimulus** (what the participant must judge) sets its model on the object (`scene`). An example is the characters in `experiments/03_find_the_pictured_character.tres`.
- **Decoration** lives in a `RiverSkin` (`skins/lagoon/lagoon_skin.tres`): the scenery, a model per placeholder shape (sphere → clownfish, box → grey fish, ...), exceptions by object name (`object_scenes`) and the spear model. Each experiment picks its look (`Experiment.look`). New experiments start with the lagoon; clear it for the plain high-contrast placeholder version. Because the skin maps shapes, a new experiment made of placeholder shapes gets models without editing the skin. `hide_with_scenery` on **RiverGame** lists the template nodes (floor, table, ...) that are hidden while scenery is shown.
- Models are always scaled to the config's `size` and centred. To turn a model or loop its animation, wrap it in a scene whose root uses `SkinModel` (see `skins/lagoon/models/*.tscn`). The spear model has its tip at the origin and points −Z.
- `Scenery` copies its `environment` (sky, fog, colour grading) onto the world environment while it is loaded, and restores the original when removed.
- Logs record which visual each object actually showed (`visual`).

## Rules
Speeds are compared by absolute value, and ties all count as correct. "same as reference" compares object ids.

**Custom rule:** make a script that `extends TaskRule` and overrides `find_targets(objects, task) -> Array[RiverObject]`, then set the task's `rule` to **custom** and put the script in `custom_rule`. `tag_rule.gd` is a 15-line example.

## Example experiment: find the character from a 2D image
`experiments/03_find_the_pictured_character.tres` runs 10 trials. Five characters stand still and spin at 400°/s. The task panel shows a 2D picture of one of them, and the player must spear that character.
- Five embedded objects: `scene` = the model, `picture` = its PNG, `spin_speed_deg_per_s` = 400, `swim_speed_m_per_s` = 0.
- One task: "Catch this one!", rule **same as reference**, the five objects, `each_object_as_reference` on, `repeat_times` = 2. That gives 5 × 2 = 10 trials, and `shuffle_trial_order` mixes them.
- The pictures in `art/characters/pictures/` come from `tools/reference_image_maker.tscn`. Open it, pick the experiment in the Inspector and press **F6**.

## Harpoon (fixed input conditions)
- Selection is geometric and deterministic. The picked object is the one whose pick sphere is at the smallest angle from the aim ray, as long as that angle is within `assist_angle`. There is no physics, spread or recoil.
- On confirm the target is chosen and `fired` is emitted first. The spear animation plays after that and never changes the result.

## Logs
Everything goes to `user://trial_logs/`. The menu shows the full path at the bottom.

| File | One row per | Use it to |
|---|---|---|
| `sessions.csv` | run | see what was run: session id, participant, experiment, start and end, `completed` / `aborted` / `quit`, trials done, accuracy, mean response time |
| `trials.csv` | trial, all runs appended | analyse: participant, experiment, task, reference, rule, outcome, response time, and the selected and correct objects with their speeds |
| `runs/<session id>.jsonl` | trial (one JSON line) | dig deeper: the experiment setup, every spawned object (all config values, visual, start position), every selection and miss with its aim ray |

A session id reads `<date>_<time>_<participant>_<experiment>`, for example `2026-09-29_14-03-11_P007_fastest_of_five_identical_fish`, so a run can be found by its name. To replay a run's layouts, set the experiment's `fixed_seed` to the logged `seed`.

`user://` is `%APPDATA%\Godot\app_userdata\<project>\` on Windows, `~/Library/Application Support/Godot/app_userdata/<project>/` on macOS, and the app's private folder on the Quest. To copy the Quest logs to `logs/quest/`, connect the headset over USB and run `python tools/pull_logs.py` (debug builds only).

## Exporting for PC / Mac
Use **Project > Export**. The **Windows Desktop** and **macOS** presets are included; install the export templates when Godot asks. The Mobile renderer runs on Direct3D 12 or Vulkan on Windows and on Metal on macOS. OpenXR is skipped automatically when there is no headset.
