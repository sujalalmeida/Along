"""Write Finder's installer layout directly, without automating the user's Finder."""
import pathlib
import sys
from ds_store import DSStore
from mac_alias import Alias

volume = pathlib.Path(sys.argv[1])
with DSStore.open(str(volume / '.DS_Store'), 'w+') as store:
    store['.']['vSrn'] = ('long', 1)
    store['.']['icvl'] = ('type', b'icnv')
    store['.']['bwsp'] = {
        'WindowBounds': '{{200, 160}, {660, 440}}',
        'ShowToolbar': False, 'ShowSidebar': False, 'ContainerShowSidebar': False,
        'ShowStatusBar': False, 'ShowPathbar': False, 'ShowTabView': False,
        'PreviewPaneVisibility': False, 'SidebarWidth': 180,
    }
    store['.']['icvp'] = {
        'viewOptionsVersion': 1, 'backgroundType': 2,
        'backgroundColorRed': 1.0, 'backgroundColorGreen': 1.0, 'backgroundColorBlue': 1.0,
        'backgroundImageAlias': Alias.for_file(str(volume / '.background' / 'installer.png')).to_bytes(),
        'iconSize': 96.0, 'textSize': 13.0, 'gridSpacing': 100.0,
        'gridOffsetX': 0.0, 'gridOffsetY': 0.0, 'arrangeBy': 'none',
        'labelOnBottom': True, 'showIconPreview': True, 'showItemInfo': False,
        'scrollPositionX': 0.0, 'scrollPositionY': 0.0,
    }
    store['Along.app']['Iloc'] = (180, 200)
    store['Applications']['Iloc'] = (480, 200)
    store['Read Me.txt']['Iloc'] = (575, 275)
