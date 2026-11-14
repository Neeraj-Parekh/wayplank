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

using Plank;

namespace Docky
{
	/**
	 * Nyx inside Wayplank.
	 *
	 * Nyx's island rewrites $XDG_RUNTIME_DIR/nyx-status.ini whenever the
	 * phone, its battery or connection, or the crossover change
	 * (app/nyx_status.py in Neeraj-Parekh/nyx-continuity). This item watches
	 * that file - no polling, no D-Bus, nothing Nyx has to answer - and runs
	 * Nyx's actions through the command the file names ([nyx] ctl), so
	 * nothing needs to be on PATH. With Nyx's "Show the dock in: Wayplank"
	 * setting, this is the dock's face and Nyx's own dock window stays
	 * hidden.
	 *
	 * Left click opens the Hub. Files dropped on it go to the phone. The
	 * menu lists the actions the file lists; the ones that need Nyx Dock
	 * are greyed out while it is not running.
	 */
	public class NyxDockItem : DockletItem
	{
		const string STATUS_NAME = "nyx-status.ini";
		const string FALLBACK_CTL = "nyx-ctl";

		FileMonitor? status_monitor = null;
		string ctl = FALLBACK_CTL;
		bool have_status = false;
		bool island = false;
		bool dock = false;
		bool crossing = false;
		bool online = false;
		string phone_name = "";
		string[] action_order = {};
		Gee.HashMap<string, string> action_labels = new Gee.HashMap<string, string> ();
		Gee.HashMap<string, string> action_icons = new Gee.HashMap<string, string> ();
		Gee.HashSet<string> action_needs_dock = new Gee.HashSet<string> ();

		/**
		 * {@inheritDoc}
		 */
		public NyxDockItem.with_dockitem_file (GLib.File file)
		{
			GLib.Object (Prefs: new DockItemPreferences.with_file (file));
		}

		construct
		{
			Icon = "phone-symbolic;;phone;;smartphone;;computer";
			Text = _("Nyx");
			reload ();

			var status = File.new_for_path (status_path ());
			try {
				status_monitor = status.monitor_file (FileMonitorFlags.NONE);
				status_monitor.changed.connect (status_changed);
			} catch (Error e) {
				warning ("Nyx: cannot watch '%s': %s", status.get_path (), e.message);
			}
		}

		~NyxDockItem ()
		{
			if (status_monitor != null) {
				status_monitor.changed.disconnect (status_changed);
				status_monitor.cancel ();
				status_monitor = null;
			}
		}

		static string status_path ()
		{
			return Path.build_filename (Environment.get_user_runtime_dir (), STATUS_NAME);
		}

		[CCode (instance_pos = -1)]
		void status_changed (File f, File? other, FileMonitorEvent event)
		{
			// Nyx replaces the file atomically, which arrives as CREATED (or
			// DELETED when the island quits); any event is worth a re-read.
			reload ();
		}

		static string get_string_or (KeyFile kf, string group, string key, string fallback)
		{
			try {
				return kf.get_string (group, key);
			} catch (Error e) {
				return fallback;
			}
		}

		static bool get_bool_or (KeyFile kf, string group, string key, bool fallback)
		{
			try {
				return kf.get_boolean (group, key);
			} catch (Error e) {
				return fallback;
			}
		}

		static int get_int_or (KeyFile kf, string group, string key, int fallback)
		{
			try {
				return kf.get_integer (group, key);
			} catch (Error e) {
				return fallback;
			}
		}

		void reload ()
		{
			var kf = new KeyFile ();
			try {
				kf.load_from_file (status_path (), KeyFileFlags.NONE);
			} catch (Error e) {
				have_status = false;
				island = dock = crossing = online = false;
				phone_name = "";
				Text = _("Nyx isn't running - click to start it");
				Indicator = IndicatorState.NONE;
				State &= ~ItemState.ACTIVE;
				return;
			}

			have_status = true;
			ctl = get_string_or (kf, "nyx", "ctl", FALLBACK_CTL);
			island = get_bool_or (kf, "nyx", "island", false);
			dock = get_bool_or (kf, "nyx", "dock", false);
			crossing = get_bool_or (kf, "nyx", "crossing", false);
			phone_name = get_string_or (kf, "phone", "name", "");
			online = get_bool_or (kf, "phone", "online", false);
			var transport = get_string_or (kf, "phone", "transport", "");
			var battery = get_int_or (kf, "phone", "battery", -1);
			var charging = get_bool_or (kf, "phone", "charging", false);

			if (!island) {
				Text = _("Nyx isn't running - click to start it");
			} else if (phone_name == "") {
				Text = _("Nyx - no phone yet");
			} else if (crossing) {
				Text = _("%s - the cursor is on the phone").printf (phone_name);
			} else if (!online) {
				Text = _("%s - not connected").printf (phone_name);
			} else {
				var parts = new Gee.ArrayList<string> ();
				parts.add (phone_name);
				if (battery >= 0)
					parts.add (charging ? _("%d%% charging").printf (battery) : "%d%%".printf (battery));
				if (transport != "")
					parts.add (transport == "usb" ? "USB" : (transport == "wifi" ? "Wi-Fi" : transport));
				Text = string.joinv (" · ", parts.to_array ());
			}

			// The running-app dot means "connected"; the active glow means the
			// cursor is on the phone - Wayplank's own crossover cue.
			Indicator = (island && online) ? IndicatorState.SINGLE : IndicatorState.NONE;
			if (crossing)
				State |= ItemState.ACTIVE;
			else
				State &= ~ItemState.ACTIVE;

			action_labels.clear ();
			action_icons.clear ();
			action_needs_dock.clear ();
			var order = get_string_or (kf, "actions", "order", "");
			action_order = order == "" ? new string[0] : order.split (";");
			foreach (var id in action_order) {
				if (id == "-" || id == "")
					continue;
				var group = "action " + id;
				action_labels[id] = get_string_or (kf, group, "label", id);
				action_icons[id] = get_string_or (kf, group, "icon", "");
				if (get_bool_or (kf, group, "needs_dock", true))
					action_needs_dock.add (id);
			}
		}

		void run_ctl (string args)
		{
			try {
				Process.spawn_command_line_async ("%s %s".printf (ctl, args));
			} catch (SpawnError e) {
				warning ("Nyx: could not run '%s %s': %s", ctl, args, e.message);
			}
		}

		void run_action (string id)
		{
			run_ctl ("run " + Shell.quote (id));
		}

		protected override AnimationType on_clicked (PopupButton button, Gdk.ModifierType mod, uint32 event_time)
		{
			if (button == PopupButton.LEFT) {
				// opens the Hub, starting Nyx's island first if it is not running
				run_action ("hub");
				return AnimationType.BOUNCE;
			}
			return AnimationType.NONE;
		}

		public override string get_drop_text ()
		{
			return phone_name != "" ? _("Send to %s").printf (phone_name) : _("Send to the phone");
		}

		protected override bool can_accept_drop (Gee.ArrayList<string> uris)
		{
			foreach (var uri in uris)
				if (uri.has_prefix ("file://"))
					return true;
			return false;
		}

		protected override bool accept_drop (Gee.ArrayList<string> uris)
		{
			var args = new StringBuilder ("send");
			var count = 0;
			foreach (var uri in uris) {
				var path = File.new_for_uri (uri).get_path ();
				if (path == null)
					continue;
				args.append (" ");
				args.append (Shell.quote (path));
				count++;
			}
			if (count == 0)
				return false;
			run_ctl (args.str);
			return true;
		}

		public override Gee.ArrayList<Gtk.MenuItem> get_menu_items ()
		{
			var items = new Gee.ArrayList<Gtk.MenuItem> ();

			if (phone_name != "")
				items.add (new TitledSeparatorMenuItem.no_line (phone_name));

			if (!have_status || action_order.length == 0) {
				var start = create_menu_item (_("Open Nyx"), "phone-symbolic;;phone", true);
				start.activate.connect (() => run_action ("hub"));
				items.add (start);
				return items;
			}

			var pending_separator = false;
			foreach (var id in action_order) {
				if (id == "-") {
					pending_separator = items.size > 0;
					continue;
				}
				if (!action_labels.has_key (id))
					continue;
				if (pending_separator) {
					items.add (new Gtk.SeparatorMenuItem ());
					pending_separator = false;
				}
				var icon = action_icons[id];
				var item = create_menu_item (action_labels[id], icon != "" ? icon : null, true);
				var action_id = id;
				item.activate.connect (() => run_action (action_id));
				if (action_needs_dock.contains (id) && !dock) {
					item.sensitive = false;
					item.tooltip_text = _("Needs Nyx Dock running");
				}
				items.add (item);
			}

			if (!dock) {
				items.add (new Gtk.SeparatorMenuItem ());
				var start_dock = create_menu_item (_("Start Nyx Dock"), "system-run-symbolic;;system-run", true);
				start_dock.activate.connect (() => run_action ("start_dock"));
				items.add (start_dock);
			}

			return items;
		}
	}
}
