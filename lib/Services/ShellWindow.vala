//
//  Copyright (C) 2026 Neeraj Parekh
//
//  Wayplank is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  Wayplank is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

//
//  Plank Wayland rebuild — lightweight window record from the Shell bridge.
//

namespace Plank
{
	public class ShellWindow : GLib.Object
	{
		public string id { get; construct; }
		public string title { get; set; }
		public bool active { get; set; }
		public bool maximized { get; set; }
		/* True when synthesized from a window count because the bridge
		 * GetWindows call is unavailable. Placeholders carry no actionable
		 * window: menus skip them, actions ignore them. They vanish on
		 * their own once real window rows arrive. */
		public bool placeholder { get; set; default = false; }

		public ShellWindow (string id, string title, bool active, bool maximized)
		{
			GLib.Object (id: id);
			this.title = title;
			this.active = active;
			this.maximized = maximized;
		}
	}
}
