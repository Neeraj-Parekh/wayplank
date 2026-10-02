//
//  Copyright (C) 2011-2012 Robert Dyer, Rico Tzschichholz
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

namespace Plank
{
	/**
	 * If/How the dock should hide itself.
	 */
	public enum HideType
	{
		/**
		 * The dock does not hide.  It should set struts to reserve space for it.
		 */
		NONE,
		/**
		 * The dock hides if a window in the active window group overlaps it.
		 */
		INTELLIGENT,
		/**
		 * The dock hides if the mouse is not over it.
		 */
		AUTO,
		/**
		 * The dock hides if there is an active maximized window.
		 */
		DODGE_MAXIMIZED,
		/**
		 * The dock hides if there is any window overlapping it.
		 */
		WINDOW_DODGE,
		/**
		 * The dock hides if there is the active window overlapping it.
		 */
		DODGE_ACTIVE,
	}
	
	/**
	 * Handles checking if a dock should hide or not.
	 */
	public class HideManager : GLib.Object
	{
		// a delay between window changes and updating our data
		// this allows window animations to occur, which might change
		// the results of our update
		const uint UPDATE_TIMEOUT = 200U;
		
#if HAVE_BARRIERS
		// FIXME Use an IconSize-based value?
		const double PRESSURE_THRESHOLD = 60.0;
		const uint PRESSURE_TIMEOUT = 1000U;
#endif
		
		static int plank_pid;
		
		static construct
		{
			plank_pid = getpid ();
		}
		
		public DockController controller { private get; construct; }
		
		/**
		 * If the dock is currently hidden.
		 */
		public bool Hidden { get; private set; default = true; }
		
		/**
		 * If hiding the dock is currently disabled
		 */
		public bool Disabled { get; private set; default = false; }
		
		/**
		 * If the dock is currently hovered by the mouse cursor.
		 */
		public bool Hovered { get; private set; default = false; }
		
		uint hide_timer_id = 0U;
		uint unhide_timer_id = 0U;
		uint prefs_changed_timer_id = 0U;
		uint geometry_timer_id = 0U;
		uint window_changed_timer_id = 0U;
		
		bool pointer_update = true;
		bool window_intersect = false;
		bool active_window_intersect = false;
		bool active_application_intersect = false;
		bool active_maximized_window_intersect = false;
		bool dialog_windows_intersect = false;
		Gdk.Rectangle last_window_rect;
		
#if HAVE_BARRIERS
		XFixes.PointerBarrier barrier = 0;
		int opcode = 0;
		double pressure = 0.0;
		uint pressure_timer_id = 0U;

		// Wayland reveal polling: pointer barriers don't exist on Wayland, and a
		// hidden (unmapped) dock receives no crossing events, so poll the pointer
		// position and reveal when it is pushed against the dock edge.
		uint reveal_poll_id = 0U;
		const uint REVEAL_TIMEOUT = 100U;
		const int REVEAL_EDGE_PX = 5;
		uint reveal_tick = 0U;
		/* Edge hold: while the pointer stays in the dock's edge strip the
		 * dock counts as hovered so intellihide can't snatch it back between
		 * reveal polls. Refreshed on every poll while in the strip. */
		int64 edge_hold_until = 0;
		const int64 EDGE_HOLD_US = 2000000;
		const int EDGE_STRIP_EXTRA = 12;
		bool barriers_supported = false;
#endif
		
		/**
		 * Creates a new instance of a HideManager, which handles
		 * checking if a dock should hide or not.
		 *
		 * @param controller the {@link DockController} to manage hiding for
		 */
		public HideManager (DockController controller)
		{
			GLib.Object (controller : controller);
		}
		
		construct
		{
			controller.prefs.notify.connect (prefs_changed);
		}
		
		/**
		 * Initializes the hide manager.  Call after the DockWindow is constructed.
		 */
		public void initialize ()
			requires (controller.window != null)
		{
			unowned DockWindow window = controller.window;

#if HAVE_BARRIERS
			initialize_barriers_support ();
#endif

			window.enter_notify_event.connect (handle_enter_notify_event);
			window.leave_notify_event.connect (handle_leave_notify_event);

			// v1 Wayland: window events arrive via the Shell bridge matcher.
			// poll_tick keeps intellihide re-evaluated every second.
			ShellMatcher.get_default ().application_opened.connect (schedule_update_from_matcher);
			ShellMatcher.get_default ().application_closed.connect (schedule_update_from_matcher);
			ShellMatcher.get_default ().active_application_changed.connect (schedule_update_from_matcher_active);
			ShellMatcher.get_default ().poll_tick.connect (schedule_update_from_tick);

			start_reveal_poll ();

			schedule_update ();
		}

		void schedule_update_from_matcher (string app_id)
		{
			schedule_update ();
		}

		void schedule_update_from_matcher_active (string? old_id, string? new_id)
		{
			schedule_update ();
		}

		void schedule_update_from_tick ()
		{
			schedule_update ();
		}
		
		~HideManager ()
		{
			unowned DockWindow window = controller.window;
			unowned DragManager drag_manager = controller.drag_manager;

			controller.prefs.notify.disconnect (prefs_changed);

			window.enter_notify_event.disconnect (handle_enter_notify_event);
			window.leave_notify_event.disconnect (handle_leave_notify_event);

			ShellMatcher.get_default ().application_opened.disconnect (schedule_update_from_matcher);
			ShellMatcher.get_default ().application_closed.disconnect (schedule_update_from_matcher);
			ShellMatcher.get_default ().active_application_changed.disconnect (schedule_update_from_matcher_active);
			ShellMatcher.get_default ().poll_tick.disconnect (schedule_update_from_tick);

			stop_timers ();
			
#if HAVE_BARRIERS
			gdk_window_remove_filter (null, (Gdk.FilterFunc)xevent_filter);
			
			if (barrier != 0) {
				unowned Gdk.X11.Display gdk_display = (controller.window.get_display () as Gdk.X11.Display);
				unowned X.Display display = gdk_display.get_xdisplay ();
				XFixes.destroy_pointer_barrier (display, barrier);
				barrier = 0;
			}
#endif
		}
		
		/**
		 * Checks to see if the dock is being hovered by the mouse cursor.
		 */
		public void update_hovered ()
		{
			unowned PositionManager position_manager = controller.position_manager;
			unowned DockWindow window = controller.window;
			
			// get current mouse pointer location
			int x, y;
			
			window.get_display ().
				get_device_manager ().get_client_pointer ().get_position (null, out x, out y);
			
			// get window location
			var win_rect = position_manager.get_dock_window_region ();
			x -= win_rect.x;
			y -= win_rect.y;
			
			update_hovered_with_coords (x, y);
		}
		
		/**
		 * Checks to see if the dock is being hovered by the mouse cursor.
		 *
		 * @param x the x coordinate of the pointer relative to the dock window
		 * @param y the y coordinate of the pointer relative to the dock window
		 */
		public void update_hovered_with_coords (int x, int y)
		{
			unowned PositionManager position_manager = controller.position_manager;
			unowned DockWindow window = controller.window;
			unowned DragManager drag_manager = controller.drag_manager;
			
			freeze_notify ();
			
			bool update_needed = false;
			
			// compute rect of the window
			var dock_rect = position_manager.get_cursor_region ();
			
			// use the dock rect and cursor location to determine if dock is hovered
			var hovered = (x >= dock_rect.x && x < dock_rect.x + dock_rect.width
				&& y >= dock_rect.y && y < dock_rect.y + dock_rect.height);
			
			if (Hovered != hovered) {
				Hovered = hovered;
				update_needed = true;
			}
			
			// disable hiding if menu is visible or drags are active
			var disabled = (window.menu_is_visible () || drag_manager.InternalDragActive || drag_manager.ExternalDragActive);
			if (Disabled != disabled) {
				Disabled = disabled;
				update_needed = true;
			}
			
			if (update_needed)
				update_hidden ();
			
			thaw_notify ();
		}
		
		void prefs_changed (Object prefs, ParamSpec prop)
		{
			switch (prop.name) {
			case "HideMode":
			case "Position":
				if (prefs_changed_timer_id > 0U) {
					GLib.Source.remove (prefs_changed_timer_id);
					prefs_changed_timer_id = 0U;
				}
				
				prefs_changed_timer_id = Gdk.threads_add_timeout (UPDATE_TIMEOUT, () => {
					update_window_intersect ();
#if HAVE_BARRIERS
					update_barrier ();
#endif
					prefs_changed_timer_id = 0U;
					return false;
				});
				break;
			case "PressureReveal":
#if HAVE_BARRIERS
				update_barrier ();
#endif
				break;
			default:
				// Nothing important for us changed
				break;
			}
		}
		
		void update_hidden ()
		{
			bool was_hidden = Hidden;

			if (Disabled) {
				if (Hidden)
					Hidden = false;
			} else if (edge_held ()) {
				show ();
			} else {
				switch (controller.prefs.HideMode) {
			default:
			case HideType.NONE:
				show ();
				break;
			
			case HideType.INTELLIGENT:
				if (Hovered || !active_application_intersect)
					show ();
				else
					hide ();
				break;
			
			case HideType.AUTO:
				if (Hovered)
					show ();
				else
					hide ();
				break;
			
			case HideType.DODGE_MAXIMIZED:
				if (Hovered || !(active_maximized_window_intersect || dialog_windows_intersect))
					show ();
				else
					hide ();
				break;
			
			case HideType.WINDOW_DODGE:
				if (Hovered || !window_intersect)
					show ();
				else
					hide ();
				break;
			
			case HideType.DODGE_ACTIVE:
				if (Hovered || !active_window_intersect)
					show ();
				else
					hide ();
				break;
			}
			pointer_update = true;
			if (was_hidden != Hidden)
				warning ("HIDETRACE hidden %s -> %s", was_hidden.to_string (), Hidden.to_string ());
			}
		}

		void hide ()
		{
			if (unhide_timer_id > 0U) {
				GLib.Source.remove (unhide_timer_id);
				unhide_timer_id = 0U;
			}
			
			if (Hidden)
				return;
			
			if (controller.prefs.HideDelay == 0U) {
				if (!Hidden)
					Hidden = true;
				return;
			}
			
			if (hide_timer_id > 0U)
				return;
			
			hide_timer_id = Gdk.threads_add_timeout (controller.prefs.HideDelay, () => {
				if (!Hidden)
					Hidden = true;
				hide_timer_id = 0U;
				return false;
			});
		}

		void show ()
		{
			bool was_hidden = Hidden;

			if (hide_timer_id > 0U) {
				GLib.Source.remove (hide_timer_id);
				hide_timer_id = 0U;
			}

			if (!Hidden) {
				finish_show (was_hidden);
				return;
			}

			if (!pointer_update || controller.prefs.UnhideDelay == 0U) {
				if (Hidden)
					Hidden = false;
				finish_show (was_hidden);
				return;
			}

			if (unhide_timer_id > 0U)
				return;

			unhide_timer_id = Gdk.threads_add_timeout (controller.prefs.UnhideDelay, () => {
				if (Hidden)
					Hidden = false;
				unhide_timer_id = 0U;
				finish_show (was_hidden);
				return false;
			});
		}

		/* On Wayland there is no always-on-top: explicitly raise the dock
		 * window every time it is revealed so it lands above applications.
		 * (May take keyboard focus on reveal; acceptable v1 trade-off.) */
		void finish_show (bool was_hidden)
		{
			if (was_hidden && !Hidden) {
				warning ("SHOWTRACE revealed, presenting above apps");
				controller.window.present ();
			}
		}
		
		[CCode (instance_pos = -1)]
		bool handle_enter_notify_event (Gtk.Widget widget, Gdk.EventCrossing event)
		{
			if (event.detail == Gdk.NotifyType.INFERIOR)
				return Hidden;
			
#if HAVE_BARRIERS
			if (Hidden && barriers_supported
				&& controller.prefs.PressureReveal
				&& device_supports_pressure (event.get_source_device ()))
				return Hidden;
#endif
			
			if (!Hovered)
				update_hovered_with_coords ((int) event.x, (int) event.y);
			
			return Hidden;
		}
		
		[CCode (instance_pos = -1)]
		bool handle_leave_notify_event (Gtk.Widget widget, Gdk.EventCrossing event)
		{
			if (event.detail == Gdk.NotifyType.INFERIOR)
				return Gdk.EVENT_PROPAGATE;
			
			// ignore this event if it was sent explicitly
			if ((bool) event.send_event)
				return Gdk.EVENT_PROPAGATE;
			
			if (Hovered)
				update_hovered_with_coords ((int) event.x, (int) event.y);
			
			return Gdk.EVENT_PROPAGATE;
		}
		
		inline bool device_supports_pressure (Gdk.Device device)
		{
			return (device.input_source == Gdk.InputSource.MOUSE
				|| device.input_source == Gdk.InputSource.TOUCHPAD);
		}
		
		//
		// intelligent hiding code
		//
		
		void update_window_intersect ()
		{
			// v1 Wayland: no per-window geometry (no Wnck). Intellihide hides
			// the dock when the active window is maximized/fullscreen, or when
			// any tracked window is maximized (it is assumed to cover the dock).
			var intersect = false;
			var active_intersect = false;
			var active_maximized_intersect = false;

			string active_id = "";
			bool maximized = false, fullscreen = false;
			if (ShellMatcher.get_default ().bridge.get_active_window (out active_id, out maximized, out fullscreen)) {
				active_intersect = true;
				if (maximized || fullscreen) {
					intersect = true;
					active_maximized_intersect = true;
				}
			}

			if (!intersect && ShellMatcher.get_default ().bridge.any_window_maximized ()) {
				intersect = true;
				active_maximized_intersect = true;
			}

			window_intersect = intersect;
			dialog_windows_intersect = false;
			active_application_intersect = active_intersect;
			active_window_intersect = active_intersect;
			active_maximized_window_intersect = active_maximized_intersect;

			pointer_update = false;
			update_hidden ();
		}
		
		void schedule_update ()
		{
			if (window_changed_timer_id > 0U)
				return;
			
			window_changed_timer_id = Gdk.threads_add_timeout (UPDATE_TIMEOUT, () => {
				update_window_intersect ();
				window_changed_timer_id = 0U;
				return false;
			});
		}
		
		void handle_workspace_changed ()
		{
			schedule_update ();
		}

		void handle_active_window_changed ()
		{
			schedule_update ();
		}

		void setup_active_window ()
		{
			schedule_update ();
		}

		void handle_state_changed ()
		{
			schedule_update ();
		}

		void handle_geometry_changed ()
		{
			schedule_update ();
		}
		
		void stop_timers ()
		{
			if (geometry_timer_id > 0U) {
				GLib.Source.remove (geometry_timer_id);
				geometry_timer_id = 0U;
			}
			
			if (window_changed_timer_id > 0U) {
				GLib.Source.remove (window_changed_timer_id);
				window_changed_timer_id = 0U;
			}
			
			if (prefs_changed_timer_id > 0U) {
				GLib.Source.remove (prefs_changed_timer_id);
				prefs_changed_timer_id = 0U;
			}
			
			if (hide_timer_id > 0U) {
				GLib.Source.remove (hide_timer_id);
				hide_timer_id = 0U;
			}
			
			if (unhide_timer_id > 0U) {
				GLib.Source.remove (unhide_timer_id);
				unhide_timer_id = 0U;
			}

			stop_reveal_poll ();
		}

		void start_reveal_poll ()
		{
			if (reveal_poll_id != 0U)
				return;

			reveal_poll_id = GLib.Timeout.add (REVEAL_TIMEOUT, () => {
				check_reveal_poll ();
				return true;
			});
		}

		void stop_reveal_poll ()
		{
			if (reveal_poll_id > 0U) {
				GLib.Source.remove (reveal_poll_id);
				reveal_poll_id = 0U;
			}
		}

		void check_reveal_poll ()
		{
			reveal_tick++;
			if (!Hidden || controller.prefs.HideMode == HideType.NONE)
				return;

			int x = 0, y = 0;
			if (!query_pointer_xwayland (out x, out y))
				return;

			bool at_edge = false;
			unowned Gdk.Screen screen = Gdk.Screen.get_default ();
			switch (controller.prefs.Position) {
			case Gtk.PositionType.TOP:
				at_edge = (y <= REVEAL_EDGE_PX);
				break;
			case Gtk.PositionType.BOTTOM:
				at_edge = (y >= screen.get_height () - REVEAL_EDGE_PX);
				break;
			case Gtk.PositionType.LEFT:
				at_edge = (x <= REVEAL_EDGE_PX);
				break;
			case Gtk.PositionType.RIGHT:
				at_edge = (x >= screen.get_width () - REVEAL_EDGE_PX);
				break;
			}

			if (at_edge) {
				warning ("REVEALTRACE edge-push at x=%d y=%d", x, y);
				edge_hold_until = GLib.get_monotonic_time () + EDGE_HOLD_US;
				show ();
			} else if (in_edge_strip (x, y)) {
				edge_hold_until = GLib.get_monotonic_time () + EDGE_HOLD_US;
			}
		}

		bool edge_held ()
		{
			return GLib.get_monotonic_time () < edge_hold_until;
		}

		/* True while the pointer is anywhere over the dock's edge strip
		 * (dock region plus a small margin), so the dock stays put while
		 * the user moves from the screen edge down into it. */
		bool in_edge_strip (int x, int y)
		{
			var rect = controller.position_manager.get_static_dock_region ();
			switch (controller.prefs.Position) {
			case Gtk.PositionType.TOP:
				return y <= rect.y + rect.height + EDGE_STRIP_EXTRA;
			case Gtk.PositionType.BOTTOM:
				return y >= rect.y - EDGE_STRIP_EXTRA;
			case Gtk.PositionType.LEFT:
				return x <= rect.x + rect.width + EDGE_STRIP_EXTRA;
			case Gtk.PositionType.RIGHT:
				return x >= rect.x - EDGE_STRIP_EXTRA;
			default:
				return false;
			}
		}

		static X.Display? xdisplay = null;
		static int xfail_count = 0;

		/* True pointer position via XWayland. GDK's get_pointer returns
		 * (0,0) on Wayland; XWayland mirrors the global pointer. The
		 * socket name changes across reboots (:0, :1, ...), so probe all. */
		static bool query_pointer_xwayland (out int x, out int y)
		{
			x = 0;
			y = 0;
			if (xdisplay == null) {
				for (var i = 0; i < 8; i++) {
					xdisplay = new X.Display (":" + i.to_string ());
					if (xdisplay != null)
						break;
				}
				if (xdisplay == null)
					return false;
			}
			X.Window root_ret = 0, child_ret = 0;
			int rx = 0, ry = 0, wx = 0, wy = 0;
			uint mask = 0;
			if (!xdisplay.query_pointer (xdisplay.default_root_window (),
				out root_ret, out child_ret, out rx, out ry, out wx, out wy, out mask)) {
				// Drop stale connections (e.g. XWayland cycled) so the next
				// poll reopens fresh instead of failing forever.
				if (++xfail_count >= 3) {
					xdisplay = null;
					xfail_count = 0;
				}
				return false;
			}
			xfail_count = 0;
			x = rx;
			y = ry;
			return true;
		}
		
#if HAVE_BARRIERS
		void initialize_barriers_support ()
		{
			// Pointer barriers are X11-only; on Wayland reveal tracking
			// falls back to the pointer/pressure path.
			if (!environment_is_session_type (XdgSessionType.X11)) {
				barriers_supported = false;
				return;
			}
			unowned Gdk.X11.Display gdk_display = (controller.window.get_display () as Gdk.X11.Display);
			unowned X.Display display = gdk_display.get_xdisplay ();
			int error_base, first_event_return;
			
			gdk_window_remove_filter (null, (Gdk.FilterFunc)xevent_filter);
			
			if (!display.query_extension ("XInputExtension", out opcode, out first_event_return, out error_base)) {
				debug ("Barriers disabled (XInput needed)");
				barriers_supported = false;
			} else {
				int major = 2, minor = 3;
				var has_xinput = (XInput.query_version (display, ref major, ref minor) == X.Success);
				if (has_xinput && major >= 2 && minor >= 3) {
					message ("Barriers enabled (XInput %i.%i support)\n", major, minor);
					barriers_supported = true;
					gdk_window_add_filter (null, (Gdk.FilterFunc)xevent_filter);
				} else {
					debug ("Barriers disabled (XInput %i.%i not sufficient)", major, minor);
					barriers_supported = false;
				}
			}
		}

		/**
		 * Event filter method needed to fetch X.Events
		 */
		[CCode (instance_pos = -1)]
		Gdk.FilterReturn xevent_filter (Gdk.XEvent gdk_xevent, Gdk.Event gdk_event)
		{
			X.Event* xevent = (X.Event*) gdk_xevent;
			X.GenericEventCookie* xcookie = &xevent.xcookie;
			unowned X.Display display = xcookie.display;
			
			// Did we got a barrier-event?
			if (barrier == 0
				|| (xcookie.extension != opcode)
				|| (xcookie.evtype != XInput.EventType.BARRIER_HIT && xcookie.evtype != XInput.EventType.BARRIER_LEAVE))
				return Gdk.FilterReturn.CONTINUE;
			
			X.get_event_data (display, xcookie);
			
			// Does it match our registered barrier?
			XInput.BarrierEvent* barrier_event = (XInput.BarrierEvent*) (xcookie.data);
			if (barrier_event.barrier != barrier) {
				X.free_event_data (display, xcookie);
				return Gdk.FilterReturn.CONTINUE;
			}
			
			switch (xcookie.evtype) {
			case XInput.EventType.BARRIER_HIT:
				double slide = 0.0, distance = 0.0;
				switch (controller.position_manager.Position) {
				default:
				case Gtk.PositionType.BOTTOM:
				case Gtk.PositionType.TOP:
					distance = Math.fabs (barrier_event.dy);
					slide = Math.fabs (barrier_event.dx);
					break;
				case Gtk.PositionType.LEFT:
				case Gtk.PositionType.RIGHT:
					distance = Math.fabs (barrier_event.dx);
					slide = Math.fabs (barrier_event.dy);
					break;
				}
				
				if (slide < distance) {
					distance = Math.fmin (15.0, distance);
					pressure += distance;
					Logger.verbose ("HideManager (pressure = %f)", pressure);
				}
				
				if (pressure >= PRESSURE_THRESHOLD) {
					pressure = 0.0;
					
					if (pressure_timer_id > 0U) {
						GLib.Source.remove (pressure_timer_id);
						pressure_timer_id = 0U;
					}
					
					Logger.verbose ("HideManager (pressure-threshold reached > unhide (%f))", PRESSURE_THRESHOLD);
					
					freeze_notify ();
					
					if (!Hovered) {
						Hovered = true;
						update_hidden ();
					}
					
					thaw_notify ();
				}
				break;
			case XInput.EventType.BARRIER_LEAVE:
				if (pressure_timer_id == 0U)
					pressure_timer_id = Gdk.threads_add_timeout (PRESSURE_TIMEOUT, () => {
						pressure = 0.0;
						pressure_timer_id = 0U;
						return false;
					});
				break;
			default:
				break;
			}
			
			XInput.barrier_release_pointer (display, barrier_event.deviceid,
				barrier, barrier_event.eventid);
			
			display.flush ();
			
			X.free_event_data (display, xcookie);
			return Gdk.FilterReturn.REMOVE;
		}
		
		public void update_barrier ()
		{
			if (!barriers_supported)
				return;
			
			unowned Gdk.X11.Display gdk_display = (controller.window.get_display () as Gdk.X11.Display);
			unowned X.Display display = gdk_display.get_xdisplay ();
			
			if (barrier > 0) {
				XFixes.destroy_pointer_barrier (display, barrier);
				barrier = 0;
			}
			
			if (!controller.prefs.PressureReveal)
				return;
			
			if (controller.prefs.HideMode == HideType.NONE)
				return;
			
			var root_xwindow = display.default_root_window ();
			var barrier_area = controller.position_manager.get_barrier ();
			
			// Enable barrier events
			uchar[] mask_bits = new uchar[XInput.mask_length (XInput.EventType.LASTEVENT)];
			XInput.EventMask mask = { XInput.ALL_MASTER_DEVICES, (int) (sizeof (uchar) * mask_bits.length), (owned) mask_bits };
			XInput.set_mask (mask.mask, XInput.EventType.BARRIER_HIT);
			XInput.set_mask (mask.mask, XInput.EventType.BARRIER_LEAVE);
			XInput.select_events (display, root_xwindow, &mask, 1);

			debug ("Barrier: %i,%i - %i,%i\n", barrier_area.x, barrier_area.y, barrier_area.x + barrier_area.width, barrier_area.y + barrier_area.height);
			
			barrier = XFixes.create_pointer_barrier (
				display, root_xwindow,
				barrier_area.x, barrier_area.y, barrier_area.x + barrier_area.width,
				barrier_area.y + barrier_area.height,
				0,
				0, null);
			
			warn_if_fail (barrier > 0);
		}
#endif
	}
}
