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
