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
		/* Edge re-arm: reveal fires only on a fresh ENTRY into the edge
		 * strip, not on mere presence. After a reveal the edge disarms and
		 * stays disarmed until the pointer leaves well past the strip
		 * (REARM_PX). Without this a parked pointer at the screen edge
		 * re-triggers show() on every poll -> endless show/hide loop. */
		bool edge_armed = true;
		const int REARM_PX = 48;
		/* Reveal rate limit: at most one reveal per interval, no matter how
		 * many fresh entries arrive. External actors (e.g. a cursor-crossover
		 * tool yanking the pointer across the edge and back) can otherwise
		 * generate entry/exit cycles no re-arming can tell apart from real
		 * pushes. The entry is still consumed (disarmed) so a parked pointer
		 * can't bank up reveals. Deliberate summons are slower than this. */
		int64 last_reveal_us = 0;
		const int64 REVEAL_MIN_INTERVAL_US = 4000000;
		/* Edge dwell: a reveal needs the pointer to sit AT the edge for
		 * several consecutive polls, not just pass through. Browser tabs
		 * live inside the edge strip, so fast tab clicks slam through y<=5
		 * for 1-3 polls on the way -- without dwell counting those slams
		 * would summon the dock on every tab switch. A deliberate summon
		 * (resting at the edge) counts 8 polls = ~800ms then reveals. */
		uint edge_dwell = 0U;
		const uint EDGE_DWELL_POLLS = 8U;
		/* Edge hold: while the pointer stays in the dock's edge strip the
		 * dock counts as hovered so intellihide can't snatch it back between
		 * reveal polls. Refreshed on every poll while in the strip. */
		int64 edge_hold_until = 0;
		/* Short grace so travel from the edge into the dock isn't cut off.
		 * Kept small on purpose: a long hold outlives quick visits (e.g. a
		 * tab click) and forces phantom reveals via update_hidden(). */
		const int64 EDGE_HOLD_US = 500000;
		const int EDGE_STRIP_EXTRA = 12;
		uint hover_stuck_count = 0U;
		/* Watchdog for the hidden state: while the dock is unmapped no
		 * crossing events arrive, so a stale Hovered=true would otherwise
		 * sit there until the next scheduled update pops the dock alone. */
		uint hidden_stuck_hover_count = 0U;
		bool barriers_supported = false;
		/* Circuit breaker: if the dock cycles show/hide rapidly (pointer
		 * tussles, cover-surface flapping, event noise -- anything), lock it
		 * hidden for a cooldown instead of dancing forever. 4 transitions =
		 * 2 full show+hide cycles inside 20s trips it (deliberately
		 * sensitive; trips are journal-visible warnings). Deliberate summons
		 * during the 60s lockout are eaten; calm is worth it. */
		int64 breaker_until = 0;
		uint trans_count = 0U;
		int64 trans_window_start = 0;
		const uint BREAKER_TRANSITIONS = 4U;
		const int64 BREAKER_WINDOW_US = 20000000;
		const int64 BREAKER_COOLDOWN_US = 60000000;
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
			var now_us = GLib.get_monotonic_time ();

			/* Breaker tripped: stay hidden, no debate, until cooldown ends. */
			if (now_us < breaker_until) {
				if (!Hidden)
					Hidden = true;
				pointer_update = true;
				return;
			}

			if (breaker_until != 0) {
				/* First pass after a lockout: reset the summon state exactly
				 * the way a Preferences-flip used to do it from outside -- no
				 * stale dwell or disarm carries over into normal service. */
				breaker_until = 0;
				edge_armed = true;
				edge_dwell = 0U;
				debug ("hide lockout ended, reveal state re-armed");
			}

			if (Disabled) {
				if (Hidden) {
					debug ("forced shown: menu or drag active");
					Hidden = false;
				}
			} else if (!Hidden && edge_held ()) {
				/* Edge hold only keeps an ALREADY visible dock up while the
				 * pointer travels from the edge into it. It must never
				 * reveal a hidden one: the strip refreshes on a parked
				 * pointer (tab rows!) and a reveal-happy hold pins the
				 * dock visible with nobody asking for it. */
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
				if (Hidden) {
					/* Stays hidden. No pointer-position summons from this
					 * machine: every reveal goes through the reveal poll's
					 * guards (edge dwell ~0.8s, re-arm, rate limit) or an
					 * already-visible traversal. A pointer sitting where
					 * the dock would appear (browser tab rows!) is not a
					 * summons; that was the pinned-visible bug. */
					hide ();
				} else if (pointer_over_visible_dock ()) {
					show ();
				} else {
					hide ();
				}
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
			if (was_hidden != Hidden) {
				debug ("hide state changed: hidden %s -> %s", was_hidden.to_string (), Hidden.to_string ());
				if (now_us - trans_window_start > BREAKER_WINDOW_US) {
					trans_window_start = now_us;
					trans_count = 1U;
				} else if (++trans_count >= BREAKER_TRANSITIONS) {
					trans_count = 0U;
					breaker_until = now_us + BREAKER_COOLDOWN_US;
					warning ("wayplank: hide cycling detected, locking dock hidden for 60s");
					if (!Hidden)
						Hidden = true;
				}
			}
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
			
			hide_timer_id = GLib.Timeout.add (controller.prefs.HideDelay, () => {
				if (!Hidden)
					Hidden = true;
				hide_timer_id = 0U;
				return false;
			});
		}

		void show ()
		{
			bool was_hidden = Hidden;

			/* Breaker tripped: never start a reveal, drop pending ones. */
			if (GLib.get_monotonic_time () < breaker_until) {
				if (unhide_timer_id > 0U) {
					GLib.Source.remove (unhide_timer_id);
					unhide_timer_id = 0U;
				}
				if (!Hidden)
					Hidden = true;
				return;
			}

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

			/* g_timeout_add is the owned closure API: glib's vapi declares the
			 * SourceFunc as owned, so valac schedules the block with a real
			 * reference and frees it via destroy-notify on removal or fire.
			 * Gdk.threads_add_timeout took an unowned delegate and the
			 * generated C dropped the block right after scheduling, leaving
			 * every pending reveal timer as a use-after-free time bomb. */
			unhide_timer_id = GLib.Timeout.add (controller.prefs.UnhideDelay, () => {
				/* Completion gate: the pointer must STILL be claiming the
				 * reveal (at the edge or over the dock). Otherwise this is a
				 * stale claim from a pointer that already left (e.g. a tab
				 * click that passed through) -- drop it and stay hidden. */
				if (Hidden && !reveal_claimed ()) {
					edge_armed = true;
					unhide_timer_id = 0U;
					return false;
				}
				if (Hidden)
					Hidden = false;
				unhide_timer_id = 0U;
				finish_show (was_hidden);
				return false;
			});
		}

		/* True once the pointer sits in the dock region or the edge strip.
		 * Crossing events are unreliable on Wayland override-redirect
		 * windows, so Hovered alone can not be trusted for anything. */
		bool region_claims (int x, int y)
		{
			if (edge_at (x, y))
				return true;
			var rect = controller.position_manager.get_static_dock_region ();
			return (x >= rect.x && x < rect.x + rect.width
				&& y >= rect.y && y < rect.y + rect.height);
		}

		/* Keep-alive test for a VISIBLE dock: the pointer is over the dock
		 * window proper. Anything outside it (including the top band full
		 * of application tab bars under an overlay dock) lets the dock
		 * hide again. Falls back to Hovered only if the pointer query
		 * itself fails; the visible dock has reliable crossing events. */
		bool pointer_over_visible_dock ()
		{
			int x = 0, y = 0;
			if (!query_pointer_xwayland (out x, out y))
				return Hovered;
			var rect = controller.position_manager.get_static_dock_region ();
			return (x >= rect.x && x < rect.x + rect.width
				&& y >= rect.y && y < rect.y + rect.height);
		}

		/* Claim for reveal completion; fail OPEN on query failure so a
		 * transient hiccup never eats a genuine summon mid-transition. */
		bool reveal_claimed ()
		{
			int x = 0, y = 0;
			if (!query_pointer_xwayland (out x, out y))
				return true;
			return region_claims (x, y);
		}

		bool edge_at (int x, int y)
		{
			unowned Gdk.Screen screen = Gdk.Screen.get_default ();
			switch (controller.prefs.Position) {
			case Gtk.PositionType.TOP:
				return (y <= REVEAL_EDGE_PX);
			case Gtk.PositionType.BOTTOM:
				return (y >= screen.get_height () - REVEAL_EDGE_PX);
			case Gtk.PositionType.LEFT:
				return (x <= REVEAL_EDGE_PX);
			case Gtk.PositionType.RIGHT:
				return (x >= screen.get_width () - REVEAL_EDGE_PX);
			default:
				return false;
			}
		}

		/* On Wayland there is no always-on-top: explicitly raise the dock
		 * window every time it is revealed so it lands above applications.
		 * (May take keyboard focus on reveal; acceptable v1 trade-off.) */
		void finish_show (bool was_hidden)
		{
			if (was_hidden && !Hidden) {
				debug ("revealed, presenting above apps");
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
			if (controller.prefs.HideMode == HideType.NONE)
				return;

			int x = 0, y = 0;
			if (!query_pointer_xwayland (out x, out y))
				return;

			/* Hidden with a stale Hovered=true: the dock is unmapped, so no
			 * crossing events will fix it, and the next scheduled update
			 * would pop the dock with nobody near it. Clear it here with
			 * the same watchdog discipline the visible branch uses. */
			if (Hovered) {
				var rect = controller.position_manager.get_static_dock_region ();
				bool inside = (x >= rect.x - EDGE_STRIP_EXTRA && x < rect.x + rect.width + EDGE_STRIP_EXTRA
					&& y >= rect.y - EDGE_STRIP_EXTRA && y < rect.y + rect.height + EDGE_STRIP_EXTRA);
				if (!inside) {
					if (++hidden_stuck_hover_count >= 6U) {
						hidden_stuck_hover_count = 0U;
						debug ("hidden: stale hover cleared while dock hidden");
						Hovered = false;
					}
				} else {
					hidden_stuck_hover_count = 0U;
				}
			}

			// Hover watchdog: crossing events are unreliable on override-
			// redirect windows, so Hovered can stick true after the pointer
			// has left the dock (dock then hangs open). If the real pointer
			// stays outside the dock region, force-unhover.
			if (!Hidden) {
				var rect = controller.position_manager.get_static_dock_region ();
				bool inside = (x >= rect.x - EDGE_STRIP_EXTRA && x < rect.x + rect.width + EDGE_STRIP_EXTRA
					&& y >= rect.y - EDGE_STRIP_EXTRA && y < rect.y + rect.height + EDGE_STRIP_EXTRA);
				if (inside) {
					hover_stuck_count = 0U;
				} else if (++hover_stuck_count >= 10U) {
					hover_stuck_count = 0U;
					if (Hovered) {
						debug ("pointer outside dock, clearing stuck hover");
						Hovered = false;
						update_hidden ();
					}
				}
				return;
			}

			bool at_edge = edge_at (x, y);

			if (!at_edge)
				edge_dwell = 0U;
			if (at_edge) {
				/* Count continuous presence; pass-throughs (tab slams)
				 * reset below and never reach the dwell needed to show. */
				if (edge_dwell < EDGE_DWELL_POLLS)
					edge_dwell++;
				if (edge_armed && edge_dwell >= EDGE_DWELL_POLLS) {
					/* Fresh, rested entry into the edge: disarm until the
					 * pointer leaves the re-arm zone, then reveal -- at most
					 * once per interval (see REVEAL_MIN_INTERVAL_US). The
					 * entry is consumed either way so nothing can bank up
					 * reveals. */
					edge_armed = false;
					var now = GLib.get_monotonic_time ();
					if (now - last_reveal_us >= REVEAL_MIN_INTERVAL_US) {
						last_reveal_us = now;
						debug ("reveal edge-push at x=%d y=%d", x, y);
						edge_hold_until = now + EDGE_HOLD_US;
						show ();
					}
				}
			} else if (!in_edge_strip (x, y)) {
				/* Pointer fully gone: kill any pending (stale) unhide so a
				 * brief visit can't pop the dock out after it left, then
				 * re-arm once it is well clear. hide() on an already-hidden
				 * dock just cancels the unhide timer. */
				hide ();
				if (past_rearm (x, y))
					edge_armed = true;
			} else if (in_edge_strip (x, y)) {
				edge_hold_until = GLib.get_monotonic_time () + EDGE_HOLD_US;
			}
		}

		/* True once the pointer has left the edge strip plus a margin, so a
		 * parked pointer can't re-trigger reveals. */
		bool past_rearm (int x, int y)
		{
			unowned Gdk.Screen screen = Gdk.Screen.get_default ();
			switch (controller.prefs.Position) {
			case Gtk.PositionType.TOP:
				return (y > REVEAL_EDGE_PX + REARM_PX);
			case Gtk.PositionType.BOTTOM:
				return (y < screen.get_height () - REVEAL_EDGE_PX - REARM_PX);
			case Gtk.PositionType.LEFT:
				return (x > REVEAL_EDGE_PX + REARM_PX);
			case Gtk.PositionType.RIGHT:
				return (x < screen.get_width () - REVEAL_EDGE_PX - REARM_PX);
			default:
				return true;
			}
		}

		bool edge_held ()
		{
			return GLib.get_monotonic_time () < edge_hold_until;
		}

		/* True while the pointer is over the dock region plus a small
		 * margin, on BOTH axes: the corridor the user travels from the
		 * screen edge into the dock. An earlier version bounded only the
		 * perpendicular axis, which made the entire top band of the
		 * screen (tab bars live there) count as the dock corridor and
		 * pinned the dock visible wherever the pointer idled near the
		 * top. */
		bool in_edge_strip (int x, int y)
		{
			var rect = controller.position_manager.get_static_dock_region ();
			switch (controller.prefs.Position) {
			case Gtk.PositionType.TOP:
				return (y <= rect.y + rect.height + EDGE_STRIP_EXTRA
					&& x >= rect.x - EDGE_STRIP_EXTRA
					&& x < rect.x + rect.width + EDGE_STRIP_EXTRA);
			case Gtk.PositionType.BOTTOM:
				return (y >= rect.y - EDGE_STRIP_EXTRA
					&& x >= rect.x - EDGE_STRIP_EXTRA
					&& x < rect.x + rect.width + EDGE_STRIP_EXTRA);
			case Gtk.PositionType.LEFT:
				return (x <= rect.x + rect.width + EDGE_STRIP_EXTRA
					&& y >= rect.y - EDGE_STRIP_EXTRA
					&& y < rect.y + rect.height + EDGE_STRIP_EXTRA);
			case Gtk.PositionType.RIGHT:
				return (x >= rect.x - EDGE_STRIP_EXTRA
					&& y >= rect.y - EDGE_STRIP_EXTRA
					&& y < rect.y + rect.height + EDGE_STRIP_EXTRA);
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

					Logger.verbose ("HideManager (pressure-threshold reached > arm edge (%f))", PRESSURE_THRESHOLD);

					/* Never forge Hovered or drive the machine directly
					 * from here: that bypassed every summon guard (edge
					 * dwell, re-arm, rate limit) and made pressure-reveal
					 * dance. The barrier holds the pointer at the edge
					 * anyway, so feed the exact machinery the reveal poll
					 * uses and let the dwell gate decide; the hold grace
					 * covers travel. */
					edge_hold_until = GLib.get_monotonic_time () + EDGE_HOLD_US;
				}
				break;
			case XInput.EventType.BARRIER_LEAVE:
				if (pressure_timer_id == 0U)
					pressure_timer_id = GLib.Timeout.add (PRESSURE_TIMEOUT, () => {
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
