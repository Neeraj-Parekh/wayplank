//
//  Plank Wayland rebuild — Bamf.Application-shaped stand-in driven by the
//  Shell bridge. Exposes exactly the members ApplicationDockItem consumes
//  (states, signals, window count), so rendering and behavior stay identical.
//

namespace Plank
{
	public class ShellApplication : GLib.Object
	{
		public signal void active_changed (bool is_active);
		public signal void name_changed (string old_name, string new_name);
		public signal void running_changed (bool is_running);
		public signal void urgent_changed (bool is_urgent);
		public signal void user_visible_changed (bool user_visible);
		public signal void child_added ();
		public signal void child_removed ();
		public signal void closed ();

		public string app_id { get; construct; }
		public string desktop_file_path { get; construct; }

		bool running = false;
		bool user_visible = false;
		bool active = false;
		string app_name = "";
		Gee.ArrayList<ShellWindow> windows = new Gee.ArrayList<ShellWindow> ();

		public ShellApplication (string app_id, string desktop_file)
		{
			GLib.Object (app_id: app_id, desktop_file_path: desktop_file);
		}

		public bool is_running () { return running; }
		public bool is_user_visible () { return user_visible; }
		public bool is_active () { return active; }
		public bool is_urgent () { return false; }
		public unowned string get_desktop_file () { return desktop_file_path; }
		public unowned string get_name () { return app_name; }
		public uint get_window_count () { return windows.size; }
		public Gee.ArrayList<ShellWindow> get_windows () { return windows; }

		/* Apply one bridge poll row; emits signals for anything that changed. */
		public void update_state (string name, bool is_active, Gee.ArrayList<ShellWindow> wins)
		{
			if (!running) {
				running = true;
				running_changed (true);
			}
			if (app_name != name) {
				var old = app_name;
				app_name = name;
				name_changed (old, name);
			}
			uint old_count = windows.size;
			windows = wins;
			if (wins.size > old_count) {
				child_added ();
			} else if (wins.size < old_count) {
				child_removed ();
			}
			bool vis = wins.size > 0;
			if (vis != user_visible) {
				user_visible = vis;
				user_visible_changed (vis);
			}
			if (is_active != active) {
				active = is_active;
				active_changed (is_active);
			}
		}

		public void mark_closed ()
		{
			if (running) {
				running = false;
				running_changed (false);
			}
			if (user_visible) {
				user_visible = false;
				user_visible_changed (false);
			}
			if (active) {
				active = false;
				active_changed (false);
			}
			closed ();
		}
	}
}
