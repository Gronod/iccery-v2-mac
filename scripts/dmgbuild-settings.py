#!/usr/bin/env python3
# scripts/dmgbuild-settings.py
#
# dmgbuild settings for ICCery. Set DMG_APP, DMG_FILENAME and DMG_VOLUME_NAME
# in the environment, or accept the defaults. Background art can be supplied
# later by placing a PNG at Resources/dmg-background.png and setting
# DMG_BACKGROUND.

import os
import sys

filename = os.environ.get('DMG_FILENAME', 'ICCery.dmg')
volume_name = os.environ.get('DMG_VOLUME_NAME', 'ICCery')

# The built .app must be staged into the image. Without this the DMG mounts
# empty (#32). DMG_APP is exported by scripts/package-release.sh.
app_path = os.environ.get('DMG_APP', '')
if not app_path or not app_path.endswith('.app') or not os.path.isdir(app_path):
    sys.stderr.write(
        'error: DMG_APP must point at an existing .app bundle '
        '(got %r)\n' % app_path)
    sys.exit(1)

files = [app_path]

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
