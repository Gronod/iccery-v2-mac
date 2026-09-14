#!/usr/bin/env python3
# scripts/dmgbuild-settings.py
#
# dmgbuild settings for ICCery. scripts/package-release.sh exports
# DMG_APP, DMG_FILENAME, DMG_VOLUME_NAME, and DMG_BACKGROUND (a
# HiDPI TIFF). A missing background is a hard error — a grey
# Finder window is not an acceptable release artefact (#95).

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

# Finder on Sonoma+ ignores the legacy Alias Manager blob that
# dmgbuild 1.6.5 wrote for a PNG. Pass a flattened HiDPI TIFF and
# require dmgbuild >= 1.6.7 (bookmark-based background). See #95.
background = os.environ.get('DMG_BACKGROUND', '')
if not background or not os.path.isfile(background):
    sys.stderr.write(
        'error: DMG_BACKGROUND must point at an existing image '
        '(got %r)\n' % background)
    sys.exit(1)

icon = None

# Window size is enough for the app icon and the Applications alias.
# Bitmap is slightly larger than this rect so title-bar chrome on
# 14+ does not crop the wordmark.
window_rect = ((100, 100), (660, 400))

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
    'ICCery.app': (180, 220),
    'Applications': (480, 220),
}

# Symlink to /Applications for drag-and-drop install.
symlinks = {'Applications': '/Applications'}
