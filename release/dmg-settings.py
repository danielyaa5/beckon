import os

app = defines['app']
files = [app, defines['marker']]
symlinks = {'Applications': '/Applications'}
badge_icon = os.path.join(app, 'Contents/Resources/AppIcon.icns')
background = defines['background']
window_rect = ((200, 180), (640, 420))
icon_locations = {'Beckon.app': (170, 185), 'Applications': (470, 185)}
icon_size = 100
text_size = 15
default_view = 'icon-view'
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
include_icon_view_settings = True
include_list_view_settings = False
format = 'UDZO'
