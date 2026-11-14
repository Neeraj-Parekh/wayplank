//
//  Copyright (C) 2026 Neeraj Parekh
//
//  This file is part of Wayplank, a fork of Plank.
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

public static void docklet_init (Plank.DockletManager manager)
{
	manager.register_docklet (typeof (Docky.NyxDocklet));
}

namespace Docky
{
	/**
	 * Nyx Continuity (Neeraj-Parekh/nyx-continuity) as a docklet: the phone,
	 * its battery and connection, the crossover state, and Nyx's actions.
	 */
	public class NyxDocklet : Object, Plank.Docklet
	{
		public unowned string get_id ()
		{
			return "nyx";
		}

		public unowned string get_name ()
		{
			return _("Nyx");
		}

		public unowned string get_description ()
		{
			return _("Your phone in the dock: the Nyx Hub, App Space, Tab Mode, mirroring, clipboard and music.");
		}

		public unowned string get_icon ()
		{
			return "phone";
		}

		public bool is_supported ()
		{
			return true;
		}

		public Plank.DockElement make_element (string launcher, GLib.File file)
		{
			return new NyxDockItem.with_dockitem_file (file);
		}
	}
}
