include $(top_srcdir)/Makefile.common

AM_CFLAGS = \
	$(COVERAGE_CFLAGS) \
	-DWNCK_I_KNOW_THIS_IS_UNSTABLE \
	-include config.h \
	$(PLANK_CORE_CFLAGS) \
	$(NULL)

AM_VALAFLAGS = \
	$(COVERAGE_VALAFLAGS) \
	$(PLANK_CORE_VALAFLAGS) \
	--vapidir $(top_srcdir)/vapi \
	$(top_srcdir)/vapi/compat.vapi \
	$(top_srcdir)/vapi/config.vapi \
	--basedir $(srcdir) \
	--directory $(builddir) \
	-C \
	$(NULL)

BUILT_SOURCES = \
	wayplank.h \
	wayplank-resources.c \
	$(NULL)

libwayplankincludedir = $(includedir)/wayplank
nodist_libwayplankinclude_HEADERS = wayplank.h

vapidir = $(datadir)/vala/vapi
nodist_vapi_DATA = \
	wayplank.vapi \
	wayplank.deps \
	$(NULL)

pkgconfigdir = $(libdir)/pkgconfig
nodist_pkgconfig_DATA = wayplank.pc


lib_LTLIBRARIES = libwayplank.la

libwayplank_la_LDFLAGS = \
	$(AM_LDLAGS) \
	-no-undefined \
	-version-info "$(LT_CURRENT)":"$(LT_REVISION)":"$(LT_AGE)" \
	-export-dynamic \
	-export-symbols-regex '^plank_.*' \
	$(NULL)

libwayplank_la_VALAFLAGS = \
	$(builddir)/plank-internal.vapi \
	$(NULL)

libwayplank_la_LIBADD = \
	$(PLANK_CORE_LIBS) \
	$(COVERAGE_LDFLAGS) \
	$(LIBM) \
	$(builddir)/libwayplank-internal.la \
	$(NULL)

libwayplank_la_VALASOURCES = \
	DBusManager.vala \
	DockController.vala \
	DockPreferences.vala \
	DockRenderer.vala \
	DragManager.vala \
	HideManager.vala \
	PositionManager.vala \
	DBus/Client.vala \
	DBus/Interfaces.vala \
	Docklets/Docklet.vala \
	Docklets/DockletItem.vala \
	Docklets/DockletManager.vala \
	Drawing/Color.vala \
	Drawing/DrawingService.vala \
	Drawing/DockTheme.vala \
	Drawing/Easing.vala \
	Drawing/Renderer.vala \
	Drawing/Surface.vala \
	Drawing/SurfaceCache.vala \
	Drawing/Theme.vala \
	Factories/AbstractMain.vala \
	Factories/Factory.vala \
	Factories/ItemFactory.vala \
	Items/ApplicationDockItem.vala \
	Items/ApplicationDockItemProvider.vala \
	Items/DefaultApplicationDockItemProvider.vala \
	Items/DockContainer.vala \
	Items/DockItem.vala \
	Items/DockItemDrawValue.vala \
	Items/DockItemProvider.vala \
	Items/DockItemPreferences.vala \
	Items/DockElement.vala \
	Items/Enums.vala \
	Items/FileDockItem.vala \
	Items/PlaceholderDockItem.vala \
	Items/PlankDockItem.vala \
	Items/TransientDockItem.vala \
	Services/Environment.vala \
	Services/EnvironmentSettings.vala \
	Services/Logger.vala \
	Services/Paths.vala \
	Services/Preferences.vala \
	Services/Settings.vala \
	Services/ShellApplication.vala \
	Services/ShellBridge.vala \
	Services/ShellControl.vala \
	Services/ShellMatcher.vala \
	Services/ShellWindow.vala \
	Services/PlankStatus.vala \
	Services/System.vala \
	Services/Unity.vala \
	Services/Worker.vala \
	Widgets/CompositedWindow.vala \
	Widgets/DockWindow.vala \
	Widgets/HoverWindow.vala \
	Widgets/PoofWindow.vala \
	Widgets/PreferencesWindow.vala \
	Widgets/TitledSeparatorMenuItem.vala \
	$(NULL)

libwayplank_la_BUILT_VALASOURCES = \
	Version.vala \
	$(NULL)

nodist_libwayplank_la_SOURCES = \
	$(BUILT_SOURCES) \
	$(libwayplank_la_BUILT_VALASOURCES:.vala=.c) \
	$(libwayplank_la_VALASOURCES:.vala=.c) \
	$(NULL)

wayplank-resources.c: $(top_srcdir)/data/wayplank.gresource.xml Makefile $(shell $(GLIB_COMPILE_RESOURCES) --generate-dependencies --sourcedir $(top_srcdir)/data $(top_srcdir)/data/wayplank.gresource.xml)
	$(AM_V_GEN) XMLLINT=$(XMLLINT) $(GLIB_COMPILE_RESOURCES) --target $@ --sourcedir $(top_srcdir)/data --generate --c-name wayplank $<

wayplank.h wayplank.vapi: libwayplank_la_vala.stamp
$(libwayplank_la_VALASOURCES:.vala=.c): libwayplank_la_vala.stamp

libwayplank_la_vala.stamp build-abi: libwayplank_internal_la_vala.stamp $(libwayplank_la_VALASOURCES) $(libwayplank_la_BUILT_VALASOURCES) Makefile
	$(AM_V_VALA)$(VALAC) \
		$(AM_VALAFLAGS) $(libwayplank_la_VALAFLAGS) \
		-H wayplank.h \
		--library wayplank \
		--symbols build-abi \
		--vapi wayplank.vapi \
		--gresources $(top_srcdir)/data/wayplank.gresource.xml \
		$(filter %.vala %.c,$^)
	$(AM_V_at)touch $@

symbols: build-abi
	@cat $(builddir)/build-abi | sort > $(srcdir)/libwayplank.symbols


noinst_LTLIBRARIES = libwayplank-internal.la

libwayplank_internal_la_CFLAGS = \
	$(AM_CFLAGS) \
	-fPIC \
	-fvisibility=internal \
	$(NULL)

libwayplank_internal_la_LDFLAGS = \
	-avoid-version \
	-non_shared \
	-static \
	$(NULL)

libwayplank_internal_la_LIBADD = \
	$(PLANK_CORE_LIBS) \
	$(NULL)

libwayplank_internal_la_VALASOURCES = \
	InternalConsts.vala \
	InternalQuarks.vala \
	Services/Matcher.vala \
	Services/WindowControl.vala \
	Services/Utils.vala \
	Widgets/DockletViewModel.vala \
	$(NULL)

libwayplank_internal_la_SOURCES = \
	gtk-compat.c \
	gtk-compat.h \
	$(NULL)

nodist_libwayplank_internal_la_SOURCES = \
	$(libwayplank_internal_la_VALASOURCES:.vala=.c) \
	$(NULL)

plank-internal.h plank-internal.vapi: libwayplank_internal_la_vala.stamp
$(libwayplank_internal_la_VALASOURCES:.vala=.c): libwayplank_internal_la_vala.stamp

libwayplank_internal_la_vala.stamp: $(libwayplank_internal_la_VALASOURCES) Makefile
	$(AM_V_VALA)$(VALAC) \
		$(AM_VALAFLAGS) \
		-H plank-internal.h \
		--library plank-internal \
		--vapi plank-internal.vapi \
		$(filter %.vala %.c,$^)
	$(AM_V_at)touch $@


TESTS = abicheck.sh

CLEANFILES = \
	libwayplank_la_vala.stamp \
	libwayplank_internal_la_vala.stamp \
	$(nodist_libwayplank_la_SOURCES) \
	$(nodist_libwayplank_internal_la_SOURCES) \
	build-abi \
	wayplank.pc \
	wayplank.vapi \
	wayplank.h \
	plank-internal.vapi \
	plank-internal.h \
	Version.vala \
	$(NULL)

EXTRA_DIST = \
	$(libwayplank_la_VALASOURCES) \
	$(libwayplank_internal_la_VALASOURCES) \
	abicheck.sh \
	libwayplank.symbols \
	wayplank.deps \
	wayplank.pc.in \
	Version.vala.in \
	$(NULL)

