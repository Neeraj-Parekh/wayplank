//
//  Copyright (C) 2015 Rico Tzschichholz
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
	// Collection of constansts which don't have an user-adjustable setting (yet)

	/* Strut layout of the dock window, as reported to the window manager.
	 * This used to live in the Wnck-based WindowControl, which was removed
	 * together with the libwnck dependency; the dock still needs the enum
	 * to publish its struts. */
	public enum Struts
	{
		LEFT,
		RIGHT,
		TOP,
		BOTTOM,
		LEFT_START,
		LEFT_END,
		RIGHT_START,
		RIGHT_END,
		TOP_START,
		TOP_END,
		BOTTOM_START,
		BOTTOM_END,
		N_VALUES
	}
	
	// Duration of animations (in ms)
	public const uint DOCK_ZOOM_DURATION = 200;
	public const uint ITEM_HOVER_DURATION = 150;
	public const uint ITEM_INVALID_DURATION = 60000;
	public const uint ITEM_SCROLL_DURATION = 300;
	
	public const uint ITEM_SERIALIZATION_DELAY = 3000;

	public const uint UNITY_UPDATE_THRESHOLD_DURATION = 32;
	public const uint UNITY_UPDATE_THRESHOLD_FAST_COUNT = 3;
	
	public const string DOCKLET_URI_PREFIX = "docklet://";
	
	public const string SURFACE_STATS_DRAWING_TIME_EXCEEDED = "drawing-time-exceeded";
	
	public const uint FOLDER_MAX_FILE_COUNT = 192;
	public const uint LAUNCHER_DIR_MAX_FILE_COUNT = 128;
}
