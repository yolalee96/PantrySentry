// Matches lib/models/app_user.dart's AvatarCatalog.options order exactly.
// The schema's users.avatar_id is an INT with no catalog table defined,
// so this fixed array is the agreed mapping until a real avatars table
// exists. If you add/reorder avatars in the Flutter app, update both.
const AVATAR_KEYS = [
  'tomato',
  'carrot',
  'broccoli',
  'corn',
  'eggplant',
  'pepper',
  'potato',
  'onion',
  'garlic',
  'cucumber',
  'mushroom',
  'avocado',
];

function avatarKeyToId(key) {
  const index = AVATAR_KEYS.indexOf(key);
  return index === -1 ? null : index + 1; // 1-based, avatar_id is UNSIGNED
}

function avatarIdToKey(id) {
  if (id === null || id === undefined) return AVATAR_KEYS[0];
  const index = id - 1;
  return AVATAR_KEYS[index] ?? AVATAR_KEYS[0];
}

module.exports = { AVATAR_KEYS, avatarKeyToId, avatarIdToKey };
