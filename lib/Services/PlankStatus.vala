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

namespace Plank
{
[DBus (name = "org.wayplank.Status")]
	public class PlankStatus : GLib.Object
	{
		public int64 RunningApps ()
		{
			return ShellMatcher.instance_ref () != null
				? ShellMatcher.instance_ref ().active_launchers ().size : 0;
		}

		public int64 TrackedApps ()
		{
			return ShellMatcher.instance_ref () != null
				? ShellMatcher.instance_ref ().bridge.apps.size : 0;
		}

		public bool MatcherOk ()
		{
			return ShellMatcher.instance_ref () != null;
		}

		public bool Hidden ()
		{
			var m = Factory.main;
			if (m == null || m.PrimaryDock == null)
				return true;
			return m.PrimaryDock.hide_manager.Hidden;
		}

		public bool X11Detected ()
		{
			return environment_is_session_type (XdgSessionType.X11);
		}
	}

}
