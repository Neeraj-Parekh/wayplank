//
//  Copyright (C) 2015 Rico Tzschichholz
//
//  This file is part of Plank.
//
//  Plank is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  Plank is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

using Plank;

namespace Docky
{
	public class DesktopDockItem : DockletItem
	{
		/**
		 * {@inheritDoc}
		 */
		public DesktopDockItem.with_dockitem_file (GLib.File file)
		{
			GLib.Object (Prefs: new DockItemPreferences.with_file (file));
		}
		
		construct
		{
			Icon = "show-desktop;;resource://" + Docky.G_RESOURCE_PATH + "/icons/show-desktop.svg";
			Text = _("Show Desktop");
		}
		
		~DesktopDockItem ()
		{
		}
		
		protected override AnimationType on_clicked (PopupButton button, Gdk.ModifierType mod, uint32 event_time)
		{
			if (button == PopupButton.LEFT) {
				// The Wnck-based "toggle showing desktop" went away with the
				// libwnck dependency: its default-icon lookup aborts the
				// whole process whenever the active icon theme has no
				// "gnome-panel" icon. GNOME's own show-desktop minimises
				// every window, so do exactly that through the Shell bridge.
				var matcher = ShellMatcher.get_default ();
				foreach (var row in matcher.bridge.apps) {
					foreach (var win in matcher.bridge.get_windows_for (row.id, row.wins))
						matcher.bridge.minimize_window (win.id);
				}
				return AnimationType.BOUNCE;
			}
			
			return AnimationType.NONE;
		}
	}
}
