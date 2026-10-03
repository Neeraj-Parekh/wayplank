namespace Plank
{
[DBus (name = "org.plank.Status")]
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
