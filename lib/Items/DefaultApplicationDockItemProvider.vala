//
//  Copyright (C) 2013 Rico Tzschichholz
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
	 * The default container and controller class for managing application dock items on a dock.
	 */
	public class DefaultApplicationDockItemProvider : ApplicationDockItemProvider
	{
		public DockPreferences Prefs { get; construct; }
		
		bool current_workspace_only;
		
		/**
		 * Creates the default container for dock items.
		 *
		 * @param prefs the preferences of the dock which owns this provider
		 */
		public DefaultApplicationDockItemProvider (DockPreferences prefs, File launchers_dir)
		{
			Object (Prefs : prefs, LaunchersDir : launchers_dir);
		}
		
		construct
		{
			Prefs.notify["CurrentWorkspaceOnly"].connect (handle_setting_changed);
			Prefs.notify["PinnedOnly"].connect (handle_pinned_only_changed);
			
			current_workspace_only = Prefs.CurrentWorkspaceOnly;
			
			if (current_workspace_only)
				connect_wnck ();
		}
		
		~DefaultApplicationDockItemProvider ()
		{
			Prefs.notify["CurrentWorkspaceOnly"].disconnect (handle_setting_changed);
			Prefs.notify["PinnedOnly"].disconnect (handle_pinned_only_changed);
			
			if (current_workspace_only)
				disconnect_wnck ();
		}
		
		protected override void update_visible_elements ()
		{
			Logger.verbose ("DefaultDockItemProvider.update_visible_items ()");

			// v1 Wayland: no per-workspace window tracking yet, everything stays attached.
			// (CurrentWorkspaceOnly defaults to off.)
			foreach (var item in internal_elements)
				item.IsAttached = true;

			base.update_visible_elements ();
		}
		
		/**
		 * {@inheritDoc}
		 */
		public override void prepare ()
		{
			if (!Prefs.PinnedOnly)
				add_transient_items ();
		}

		protected override void app_opened (string app_id)
		{
			var app = ShellMatcher.get_default ().app_for_id (app_id);
			if (app == null)
				return;

			unowned ApplicationDockItem? found = item_for_shell_application (app);
			if (found != null) {
				found.App = app;
				return;
			}

			if (Prefs.PinnedOnly)
				return;

			var new_item = new TransientDockItem.with_application (app);

			add (new_item);
		}
		
		void app_closed (DockItem item)
		{
			if (item is TransientDockItem
				&& !(((TransientDockItem) item).has_unity_info ()))
				remove (item);
		}
		
		void connect_wnck ()
		{
			// v1 Wayland: workspace tracking comes from the bridge later;
			// nothing to connect yet.
		}

		void disconnect_wnck ()
		{
		}

		void handle_window_changed ()
		{
			update_visible_elements ();
		}

		void handle_workspace_changed ()
		{
			update_visible_elements ();
		}

		void handle_viewports_changed ()
		{
			update_visible_elements ();
		}
		
		void handle_setting_changed ()
		{
			if (current_workspace_only == Prefs.CurrentWorkspaceOnly)
				return;
			
			current_workspace_only = Prefs.CurrentWorkspaceOnly;
			
			if (current_workspace_only)
				connect_wnck ();
			else
				disconnect_wnck ();
			
			update_visible_elements ();
		}
		
		void handle_pinned_only_changed ()
		{
			if (Prefs.PinnedOnly)
				remove_transient_items ();
			else
				add_transient_items ();
		}
		
		void add_transient_items ()
		{
			var transient_items = new Gee.ArrayList<DockElement> ();
			
			// Match running applications to their available dock-items
			foreach (var app in ShellMatcher.get_default ().active_launchers ()) {
				unowned ApplicationDockItem? found = item_for_shell_application (app);
				if (found != null) {
					found.App = app;
					continue;
				}
				
				if (!app.is_user_visible ())
					continue;
				
				transient_items.add (new TransientDockItem.with_application (app));
			}
			
			add_all (transient_items);
		}
		
		void remove_transient_items ()
		{
			var transient_items = new Gee.ArrayList<DockElement> ();
			
			foreach (var element in internal_elements) {
				if (element is TransientDockItem)
					transient_items.add (element);
			}
			
			remove_all (transient_items);
		}
		
		protected override void connect_element (DockElement element)
		{
			base.connect_element (element);
			
			unowned ApplicationDockItem? appitem = (element as ApplicationDockItem);
			if (appitem != null) {
				appitem.app_closed.connect (app_closed);
				appitem.pin_launcher.connect (pin_item);
			}
		}
		
		protected override void disconnect_element (DockElement element)
		{
			base.disconnect_element (element);
			
			unowned ApplicationDockItem? appitem = (element as ApplicationDockItem);
			if (appitem != null) {
				appitem.app_closed.disconnect (app_closed);
				appitem.pin_launcher.disconnect (pin_item);
			}
		}
		
		protected override void handle_item_deleted (DockItem item)
		{
			unowned ShellApplication? app = null;
			if (item is ApplicationDockItem)
				app = ((ApplicationDockItem) item).App;
			
			if (app == null || !app.is_running () || Prefs.PinnedOnly) {
				remove (item);
				return;
			}
			
			var new_item = new TransientDockItem.with_application (app);
			item.copy_values_to (new_item);
			
			replace (new_item, item);
		}
		
		public void pin_item (DockItem item)
		{
			if (!internal_elements.contains (item)) {
				critical ("Item '%s' does not exist in this DockItemProvider.", item.Text);
				return;
			}
			
			Logger.verbose ("DefaultDockItemProvider.pin_item ('%s[%s]')", item.Text, item.DockItemFilename);

			unowned ApplicationDockItem? app_item = (item as ApplicationDockItem);
			if (app_item == null)
				return;
			
			// delay automatic add of new dockitems while creating this new one
			delay_items_monitor ();
			
			if (item is TransientDockItem) {
				var dockitem_file = Factory.item_factory.make_dock_item (item.Launcher, LaunchersDir);
				if (dockitem_file == null)
					return;
				
				var new_item = new ApplicationDockItem.with_dockitem_file (dockitem_file);
				item.copy_values_to (new_item);
				
				replace (new_item, item);
			} else {
				if (!(app_item.is_running () || app_item.has_unity_info ()))
					remove (item);
				item.delete ();
			}
			
			resume_items_monitor ();
		}
	}
}
