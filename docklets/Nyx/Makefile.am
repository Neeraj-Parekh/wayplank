include $(top_srcdir)/Makefile.common

VAPIDIR = $(top_srcdir)/vapi

libdocklet_nyx_la_LTLIBRARIES = libdocklet-nyx.la

libdocklet_nyx_ladir = $(pkglibdir)/docklets

libdocklet_nyx_la_VALASOURCES = \
	NyxDockItem.vala \
	NyxDocklet.vala \
	$(NULL)

nodist_libdocklet_nyx_la_SOURCES = \
	$(libdocklet_nyx_la_VALASOURCES:.vala=.c) \
	$(NULL)

libdocklet_nyx_la_VALAFLAGS = \
	$(PLANK_CORE_VALAFLAGS) \
	$(VAPIDIR)/config.vapi \
	--vapidir $(top_srcdir)/vapi \
	--vapidir $(top_builddir)/lib \
	--pkg wayplank \
	$(NULL)

libdocklet_nyx_la_LIBADD = \
	$(PLANK_CORE_LIBS) \
	$(NULL)

libdocklet_nyx_la_LDFLAGS = \
	$(DOCKLET_LDFLAGS) \
	$(PLANK_CORE_LDFLAGS) \
	$(top_builddir)/lib/libwayplank.la \
	$(NULL)

libdocklet_nyx_la_CFLAGS = \
	$(PLANK_CORE_CFLAGS) \
	-include config.h \
	-I$(top_builddir)/lib \
	$(NULL)

$(libdocklet_nyx_la_VALASOURCES:.vala=.c): libdocklet_nyx_la_vala.stamp

libdocklet_nyx_la_vala.stamp: $(libdocklet_nyx_la_VALASOURCES) $(top_builddir)/lib/wayplank.vapi Makefile
	$(AM_V_VALA)$(VALAC) \
		$(libdocklet_nyx_la_VALAFLAGS) \
		-C \
		$(filter %.vala %.c,$^)
	$(AM_V_at)touch $@

CLEANFILES = \
	libdocklet_nyx_la_vala.stamp \
	$(nodist_libdocklet_nyx_la_SOURCES) \
	$(NULL)

EXTRA_DIST = \
	$(libdocklet_nyx_la_VALASOURCES) \
	$(NULL)

