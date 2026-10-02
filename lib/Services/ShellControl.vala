//
//  Plank Wayland rebuild — WindowControl-shaped actions over the Shell bridge.
//  Same call shape the dock items already use; window operations go through
//  org.plank.Bridge instead of Wnck/Bamf.
//

namespace Plank
{
	public class ShellControl : GLib.Object
	{
		static ShellBridge? bridge = null;

		static unowned ShellBridge get_bridge ()
		{
			if (bridge == null)
				bridge = ShellMatcher.get_default ().bridge;
			return bridge;
		}

		public static void smart_focus (ShellApplication app, uint32 event_time)
		{
			// Shell raises the app (most-recent window), matching the common case
			// of focusing an inactive app or re-raising a single window.
			get_bridge ().activate (app.app_id);
		}

		public static void focus_next (ShellApplication app, uint32 event_time)
		{
			cycle_window (app, 1);
		}

		public static void focus_previous (ShellApplication app, uint32 event_time)
		{
			cycle_window (app, -1);
		}

		static Gee.ArrayList<ShellWindow> real_windows (ShellApplication app)
		{
			var wins = get_bridge ().get_windows_for (app.app_id, 0);
			var real = new Gee.ArrayList<ShellWindow> ();
			foreach (var w in wins) {
				if (!w.placeholder)
					real.add (w);
			}
			return real;
		}

		static void cycle_window (ShellApplication app, int step)
		{
			var wins = real_windows (app);
			if (wins.size == 0) {
				get_bridge ().activate (app.app_id);
				return;
			}
			if (wins.size == 1) {
				get_bridge ().activate_window (wins[0].id);
				return;
			}
			int at = 0;
			for (int i = 0; i < wins.size; i++) {
				if (wins[i].active) {
					at = i;
					break;
				}
			}
			int next = (at + step + wins.size) % wins.size;
			get_bridge ().activate_window (wins[next].id);
		}

		public static void close_all (ShellApplication app, uint32 event_time)
		{
			foreach (var w in get_bridge ().get_windows_for (app.app_id, 0)) {
				if (!w.placeholder)
					get_bridge ().close_window (w.id);
			}
		}

		public static void focus_window (ShellWindow window, uint32 event_time)
		{
			get_bridge ().activate_window (window.id);
		}

		public static Gdk.Pixbuf? get_window_icon (ShellWindow window)
		{
			// v1: per-window icons need pixel transfer over D-Bus; menus
			// already fall back to the application Icon when this is null.
			return null;
		}

		public static Gdk.Pixbuf? get_app_icon (ShellApplication app)
		{
			// v1: same fallback as above; desktop-file items use launcher icons.
			return null;
		}

		public static bool has_window_on_workspace (ShellApplication app)
		{
			// v1: workspace filtering degraded (always visible); the
			// CurrentWorkspaceOnly preference defaults to off.
			return true;
		}

		public static void update_icon_regions (ShellApplication app, Gdk.Rectangle region)
		{
			// v1 Wayland: icon geometry hints are X11 WM hints with no
			// Mutter equivalent; the dock positions itself, nothing to update.
		}
	}
}
