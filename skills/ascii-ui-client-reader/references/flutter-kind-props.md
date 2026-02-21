# Flutter Kind and Property Mapping

Use this reference to avoid flattening all components into one rectangle pattern.

## Base Node Contract

Expect each node to provide:

- `id`: stable string identifier
- `kind`: component type
- `x`, `y`, `w`, `h`: cell-based geometry
- `props`: kind-specific properties
- `children`: child node list when container-like

## Kind Mapping

| kind | Flutter target | Required props | Common optional props |
| --- | --- | --- | --- |
| `panel` | `Container` | none | `title`, `border`, `padding`, `background`, `elevation` |
| `text` | `Text` | `value` | `style`, `align`, `maxLines`, `overflow` |
| `button` | `ElevatedButton` / `OutlinedButton` | `label` | `variant`, `icon`, `enabled`, `onPressAction` |
| `input` | `TextField` / `TextFormField` | `name` | `placeholder`, `value`, `readOnly`, `maxLength`, `keyboardType` |
| `textarea` | multiline `TextField` | `name` | `placeholder`, `value`, `minLines`, `maxLines` |
| `checkbox` | `CheckboxListTile` / `Checkbox` | `label` | `checked`, `tristate`, `enabled` |
| `radio` | `RadioListTile` / `Radio` | `label`, `group` | `value`, `selected`, `enabled` |
| `toggle` | `SwitchListTile` / `Switch` | `label` | `value`, `enabled` |
| `select` | `DropdownButtonFormField` | `name`, `options` | `selected`, `placeholder`, `enabled` |
| `tabs` | `DefaultTabController` + `TabBar` + `TabBarView` | `tabs` | `activeIndex`, `scrollable` |
| `list` | `ListView` / `Column` | `items` | `itemTemplate`, `divider`, `selectionMode` |
| `table` | `DataTable` | `columns`, `rows` | `sortable`, `dense`, `showCheckboxColumn` |
| `image` | `Image.asset` / `Image.network` | `src` | `fit`, `repeat`, `semanticLabel` |
| `dialog` | `Dialog` / `AlertDialog` | `title` | `modal`, `dismissible`, `actions` |
| `chip` | `Chip` / `InputChip` | `label` | `selected`, `deletable`, `avatar` |
| `spacer` | `SizedBox` | none | `axis` |

## Overlay and Page Rules

- Keep `standalone` page roots independent.
- Render `overlay` pages above their parent page while preserving parent scene.
- Apply overlay offset relative to parent origin `(0,0)`.
- Use blocking backdrop only when overlay props request modal behavior.

## Property Editor Guidance

- Render common geometry fields (`x`, `y`, `w`, `h`) in one section.
- Render kind-specific fields in a separate section.
- Hide irrelevant fields instead of showing every possible field for every kind.
- Preserve unknown `props` keys during round-trip edits.
