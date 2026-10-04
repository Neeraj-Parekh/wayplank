include $(top_srcdir)/Makefile.common

wayplank_VALAFLAGS = \
	$(COVERAGE_VALAFLAGS) \
	$(PLANK_CORE_VALAFLAGS) \
	$(top_builddir)/lib/wayplank.vapi \
	--vapidir $(top_srcdir)/vapi \
	$(top_srcdir)/vapi/config.vapi \
	-C \
	$(NULL)

BUILT_SOURCES = wayplank_vala.stamp

bin_PROGRAMS = wayplank

wayplank_CFLAGS = \
	$(COVERAGE_CFLAGS) \
	$(PLANK_CORE_CFLAGS) \
	-include config.h \
	-I$(top_builddir)/lib \
	$(NULL)

wayplank_LDADD = \
	$(COVERAGE_LDFLAGS) \
	$(PLANK_CORE_LIBS) \
	$(top_builddir)/lib/libwayplank.la \
	$(NULL)

wayplank_LDFLAGS = \
	-L$(pkglibdir) \
	$(NULL)

wayplank_VALASOURCES = \
	Main.vala \
	$(NULL)

nodist_wayplank_SOURCES = \
	$(wayplank_VALASOURCES:.vala=.c) \
	$(NULL)

$(wayplank_VALASOURCES:.vala=.c): wayplank_vala.stamp

wayplank_vala.stamp: $(wayplank_VALASOURCES) $(top_builddir)/lib/wayplank.vapi Makefile
	$(AM_V_VALA)$(VALAC) \
		$(wayplank_VALAFLAGS) \
		$(filter %.vala %.c,$^)
	$(AM_V_at)touch $@

CLEANFILES = \
	wayplank_vala.stamp \
	$(nodist_wayplank_SOURCES) \
	$(NULL)

EXTRA_DIST = \
	$(wayplank_VALASOURCES) \
	$(NULL)

