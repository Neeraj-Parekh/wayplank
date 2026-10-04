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
//  Plank Wayland rebuild — Bamf.Matcher-shaped stand-in driven by ShellBridge.
//  Polls the bridge; diffs app-id sets; emits string-id signals that the
//  (rewired) item providers consume.
//

namespace Plank
{
	public class ShellMatcher : GLib.Object
	{
		public signal void application_opened (string app_id);
		public signal void application_closed (string app_id);
		public signal void active_application_changed (string? old_id, string? new_id);
		/* Fired after every poll so hide/intersect logic re-evaluates even
		 * when the app set itself did not change. */
		public signal void poll_tick ();

		static ShellMatcher? instance = null;

		public static ShellMatcher get_default ()
		{
			if (instance == null)
				instance = new ShellMatcher ();
			return instance;
		}

		public ShellBridge bridge { get; private set; }
		Gee.HashMap<string, ShellApplication> known = new Gee.HashMap<string, ShellApplication> ();
		string? active_id = null;
		uint poll_id = 0U;

		private ShellMatcher ()
		{
		}

		construct
		{
			bridge = new ShellBridge ();
		}

		public static ShellMatcher? instance_ref ()
		{
			return instance;
		}

		public void start_polling ()
		{
			if (poll_id != 0U)
				return;
			poll_id = GLib.Timeout.add_seconds (1, () => {
				poll_once ();
				return true;
			});
		}

		public void stop_polling ()
		{
			if (poll_id != 0U) {
				GLib.Source.remove (poll_id);
				poll_id = 0U;
			}
		}

		public void poll_once ()
		{
			// Refresh the app list; the return value only tells whether it
			// changed. The diff and poll_tick below must run on EVERY poll
			// (even unchanged/failed) so hide logic re-evaluates continuously.
			bridge.update ();

			// Never track ourselves (would add a bogus dock icon).
			var seen = new Gee.HashSet<string> ();
			foreach (var row in bridge.apps) {
				if (row.id == "plank.desktop")
					continue;
				seen.add (row.id);
				ShellApplication? app = known.get (row.id);
				if (app == null) {
					app = new ShellApplication (row.id, BridgeMatcher.desktop_file_for (row.id));
					known.set (row.id, app);
					application_opened (row.id);
				}
				app.update_state (row.name, row.active, fetch_windows (row.id, row.wins));
			}

			var gone = new Gee.ArrayList<string> ();
			foreach (var id in known.keys) {
				if (!seen.contains (id))
					gone.add (id);
			}
			foreach (var id in gone) {
				ShellApplication? app = known.get (id);
				known.unset (id);
				if (app != null)
					app.mark_closed ();
				application_closed (id);
			}

			string? now_active = null;
			foreach (var row in bridge.apps) {
				if (row.active) {
					now_active = row.id;
					break;
				}
			}
			if (now_active != active_id) {
				var old = active_id;
				active_id = now_active;
				active_application_changed (old, now_active);
			}

			poll_tick ();
		}

		Gee.ArrayList<ShellWindow> fetch_windows (string app_id, int32 count_hint)
		{
			return bridge.get_windows_for (app_id, count_hint);
		}

		public Gee.ArrayList<ShellApplication> active_launchers ()
		{
			var list = new Gee.ArrayList<ShellApplication> ();
			foreach (var app in known.values)
				list.add (app);
			return list;
		}

		public ShellApplication? app_for_id (string app_id)
		{
			return known.get (app_id);
		}
	}

	namespace BridgeMatcher
	{
		internal string desktop_file_for (string app_id)
		{
			// app_id from Shell is already a desktop-file id (e.g. firefox.desktop)
			foreach (var dir in GLib.Environment.get_system_data_dirs ()) {
				var p = GLib.Path.build_filename (dir, "applications", app_id);
				if (GLib.FileUtils.test (p, GLib.FileTest.EXISTS))
					return p;
			}
			var local = GLib.Path.build_filename (GLib.Environment.get_user_data_dir (), "applications", app_id);
			if (GLib.FileUtils.test (local, GLib.FileTest.EXISTS))
				return local;
			return "";
		}
	}
}
