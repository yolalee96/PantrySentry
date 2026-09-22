/// Fixed set of units offered in the Add/Edit Item screen's dropdown.
/// If an existing item (added before this was a dropdown, or via direct
/// API access) has a unit outside this list, the screen adds it as an
/// extra option dynamically so editing that item doesn't break — see
/// add_edit_item_screen.dart's initState.
const List<String> kUnitOptions = [
  'pcs',
  'g',
  'kg',
  'mg',
  'mL',
  'L',
  'pack',
  'box',
  'bottle',
  'can',
  'dozen',
];
