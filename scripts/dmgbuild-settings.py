#!/usr/bin/env python3
# scripts/dmgbuild-settings.py
#
# dmgbuild settings for ICCery. Set DMG_FILENAME and DMG_VOLUME_NAME in the
# environment, or accept the defaults. Background art can be supplied later by
# placing a PNG at Resources/dmg-background.png and setting DMG_BACKGROUND.

import os

filename = os.environ.get('DMG_FILENAME', 'ICCery.dmg')
volume_name = os.environ.get('DMG_VOLUME_NAME', 'ICCery')

# Background art is optional. If the referenced PNG does not exist, fall back
# to a plain window. See docs/23-assets.md for the DMG background spec.
background = os.environ.get('DMG_BACKGROUND', 'Resources/dmg-background.png')
if background and not os.path.exists(background):
    background = None

icon = None

# Window size is enough for the app icon and the Applications alias.
window_rect = ((100, 100), (640, 480))

# Use icon view without extra chrome.
default_view = 'icon-view'
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
sidebar_width = 180

# Position the .app on the left and the Applications alias on the right.
icon_locations = {
    'ICCery.app': (140, 240),
    'Applications': (500, 240),
}

# Symlink to /Applications for drag-and-drop install.
symlinks = {'Applications': '/Applications'}
