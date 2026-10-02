//
//  Plank Wayland rebuild — D-Bus consumer side of org.plank.Bridge.
//  Drop-in data source replacing Wnck/Bamf window tracking on GNOME Wayland.
//

namespace Plank
{
	public class ShellBridge : GLib.Object
	{
		public struct AppRow
		{
			public string id;
			public string name;
			public int32 wins;
			public bool active;
		}

		const string BUS_NAME = "org.plank.Bridge";
		const string OBJECT_PATH = "/org/plank/Bridge";
		const string IFACE = "org.plank.Bridge";

		GLib.DBusConnection? conn = null;
		public Gee.ArrayList<AppRow?> apps { get; private set; }

		public signal void apps_changed ();

		public ShellBridge ()
		{
			apps = new Gee.ArrayList<AppRow?> ();
		}

		public bool ensure_connection ()
		{
			if (conn != null)
				return true;
			try {
				conn = GLib.Bus.get_sync (GLib.BusType.SESSION);
				return true;
			} catch (GLib.Error e) {
				warning ("shellbridge: no session bus: %s", e.message);
				return false;
			}
		}

		/* Returns true when the visible list changed. */
		public bool update ()
		{
			if (!ensure_connection ())
				return false;
			GLib.Variant? res = null;
			try {
				res = conn.call_sync (BUS_NAME, OBJECT_PATH, IFACE, "GetRunningApps", null,
					new GLib.VariantType ("(a(ssib))"), GLib.DBusCallFlags.NONE, -1);
			} catch (GLib.Error e) {
				warning ("shellbridge: GetRunningApps failed: %s", e.message);
				return false;
			}
			var fresh = new Gee.ArrayList<AppRow?> ();
			var list = res.get_child_value (0);
			for (size_t i = 0; i < list.n_children (); i++) {
				string id = "", name = "";
				int32 nw = 0;
				bool active = false;
				list.get_child_value (i).get ("(ssib)", out id, out name, out nw, out active);
				fresh.add ({id, name, nw, active});
			}
			if (same_as (fresh))
				return false;
			apps = fresh;
			apps_changed ();
			return true;
		}

		bool same_as (Gee.ArrayList<AppRow?> other)
		{
			if (other.size != apps.size)
				return false;
			for (int i = 0; i < other.size; i++) {
				var a = apps[i];
				var b = other[i];
				if (a.id != b.id || a.name != b.name || a.wins != b.wins || a.active != b.active)
					return false;
			}
			return true;
		}

		public void activate (string app_id)
		{
			if (!ensure_connection ())
				return;
			try {
				conn.call_sync (BUS_NAME, OBJECT_PATH, IFACE, "ActivateApp",
					new GLib.Variant ("(s)", app_id), null, GLib.DBusCallFlags.NONE, -1);
			} catch (GLib.Error e) {
				warning ("shellbridge: ActivateApp failed: %s", e.message);
			}
		}

		public void launch_new (string app_id)
		{
			if (!ensure_connection ())
				return;
			try {
				conn.call_sync (BUS_NAME, OBJECT_PATH, IFACE, "LaunchApp",
					new GLib.Variant ("(s)", app_id), null, GLib.DBusCallFlags.NONE, -1);
			} catch (GLib.Error e) {
				warning ("shellbridge: LaunchApp failed: %s", e.message);
			}
		}

		public Gee.ArrayList<ShellWindow> get_windows_for (string app_id, int32 count_hint)
		{
			var wins = new Gee.ArrayList<ShellWindow> ();
			if (!ensure_connection ())
				return wins;
			GLib.Variant? res = null;
			try {
				res = conn.call_sync (BUS_NAME, OBJECT_PATH, IFACE, "GetWindows",
					new GLib.Variant ("(s)", app_id),
					new GLib.VariantType ("(a(ssbb))"), GLib.DBusCallFlags.NONE, -1);
			} catch (GLib.Error e) {
				// Bridge too old for GetWindows (or unreachable detail):
				// synthesize count placeholders so dots/menus stay correct.
				for (int32 i = 0; i < count_hint; i++) {
					var ph = new ShellWindow ("%s#%d".printf (app_id, i), "", false, false);
					ph.placeholder = true;
					wins.add (ph);
				}
				return wins;
			}
			var list = res.get_child_value (0);
			for (size_t i = 0; i < list.n_children (); i++) {
				string id = "", title = "";
				bool active = false, maximized = false;
				list.get_child_value (i).get ("(ssbb)", out id, out title, out active, out maximized);
				wins.add (new ShellWindow (id, title, active, maximized));
			}
			return wins;
		}

		/* Active window info for HideManager intellihide. */
		public bool get_active_window (out string app_id, out bool maximized, out bool fullscreen)
		{
			app_id = "";
			maximized = false;
			fullscreen = false;
			if (!ensure_connection ())
				return false;
			GLib.Variant? res = null;
			try {
				res = conn.call_sync (BUS_NAME, OBJECT_PATH, IFACE, "GetActiveWindow", null,
					new GLib.VariantType ("(ssbb)"), GLib.DBusCallFlags.NONE, -1);
			} catch (GLib.Error e) {
				return false;
			}
			string win_id = "";
			res.get ("(ssbb)", out app_id, out win_id, out maximized, out fullscreen);
			return app_id != "";
		}

		/* True when any tracked window is maximized or fullscreen.
		 * Used for intellihide: on Wayland there is no window geometry,
		 * so any maximized window is assumed to cover the dock. */
		public bool any_window_maximized ()
		{
			if (!ensure_connection ())
				return false;
			GLib.Variant? res = null;
			try {
				res = conn.call_sync (BUS_NAME, OBJECT_PATH, IFACE, "GetRunningApps", null,
					new GLib.VariantType ("(a(ssib))"), GLib.DBusCallFlags.NONE, -1);
			} catch (GLib.Error e) {
				return false;
			}
			var list = res.get_child_value (0);
			for (size_t i = 0; i < list.n_children (); i++) {
				string id = "", name = "";
				int32 nw = 0;
				bool active = false;
				list.get_child_value (i).get ("(ssib)", out id, out name, out nw, out active);
				if (nw > 0) {
					foreach (var w in get_windows_for (id, nw)) {
						if (!w.placeholder && w.maximized)
							return true;
					}
				}
			}
			return false;
		}

		public void activate_window (string win_id)
		{
			call_window_method ("ActivateWindow", win_id);
		}

		public void minimize_window (string win_id)
		{
			call_window_method ("MinimizeWindow", win_id);
		}

		public void close_window (string win_id)
		{
			call_window_method ("CloseWindow", win_id);
		}

		void call_window_method (string method, string win_id)
		{
			if (!ensure_connection ())
				return;
			try {
				conn.call_sync (BUS_NAME, OBJECT_PATH, IFACE, method,
					new GLib.Variant ("(s)", win_id), null, GLib.DBusCallFlags.NONE, -1);
			} catch (GLib.Error e) {
				warning ("shellbridge: %s failed: %s", method, e.message);
			}
		}
	}
}
