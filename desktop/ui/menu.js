/* What the menu holds: the Mac app's five icons (MenuSelectionModel), Power in the middle, and only what this system
   does. Without a profile, Controllers holds its place. Quit is last, never the first choice where there is another. */
/* Marks a text for generate.py; the page translates it. */
const t = key => key;
const POWER = [['fullscreen', t('Fullscreen'), 'monitor'], ['hide', t('Hide'), 'hidden'], ['restart', t('Restart app'), 'restartAlt'], ['quit', t('Quit'), 'power']];
export const menuOf = ({ people, abilities }) => {
  const entry = ([id, title, icon]) => ({ id, title, icon });
  const power = POWER.filter(([id]) => abilities.includes(id)).map(entry);
  return [
    people > 0 ? { id: 'profile', title: t('Profile'), icon: 'person', entries: [people > 1 && ['switch', t('Switch profile'), 'person'], ['edit', t('Edit profile'), 'edit'], ['theme', t('Theme'), 'palette']].filter(Boolean).map(entry) } : { id: 'controllers', title: t('Controllers'), icon: 'gamepad' },
    { id: 'library', title: t('Library'), icon: 'add', entries: [['add', t('Add game'), 'add'], ['sources', t('Manage sources'), 'collections'], ['refresh', t('Library refresh'), 'sync']].map(entry) },
    power.length > 0 && { id: 'power', title: t('Power'), icon: 'power', entries: power },
    { id: 'activity', title: t('Activity center'), icon: 'notifications' },
    { id: 'settings', title: t('Settings'), icon: 'settings' },
  ].filter(Boolean);
};
