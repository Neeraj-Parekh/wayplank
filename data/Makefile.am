NULL =

SUBDIRS = \
	icons \
	themes \
	$(NULL)

if ENABLE_APPORT
SUBDIRS += apport
endif

EXTRA_DIST = \
	application-default-icon.svg \
	wayplank.appdata.xml.in \
	net.launchpad.wayplank.gschema.xml.in \
	wayplank.desktop.in \
	wayplank.gresource.xml \
	poof.svg \
	ui/preferences.ui \
	$(NULL)

CLEANFILES = \
	wayplank.appdata.xml \
	wayplank.desktop \
	$(gsettings_SCHEMAS) \
	gschemas.compiled \
	net.launchpad.wayplank.gschema.valid \
	$(NULL)

applicationsdir = $(datadir)/applications
applications_DATA = wayplank.desktop

appdatadir = $(datadir)/metainfo
appdata_DATA = wayplank.appdata.xml

gsettings_SCHEMAS = net.launchpad.wayplank.gschema.xml

%.gschema.xml: %.gschema.xml.in Makefile
	$(AM_V_GEN) sed -e 's|@GETTEXT_PACKAGE[@]|$(GETTEXT_PACKAGE)|g' \
	$< > $@ || rm $@

@GSETTINGS_RULES@

gschemas.compiled: Makefile $(gsettings_SCHEMAS:.xml=.valid)
	$(AM_V_GEN) $(GLIB_COMPILE_SCHEMAS) --targetdir=$(builddir) $(builddir)

all-local: gschemas.compiled

%.desktop: %.desktop.in
	$(AM_V_GEN)$(MSGFMT) --desktop --keyword= --keyword=Name \
		--keyword=GenericName --keyword=Comment --keyword=Keywords \
		--template $< -d $(top_srcdir)/po -o $@

%.appdata.xml: %.appdata.xml.in
	$(AM_V_GEN)$(MSGFMT) --xml --template $< -d $(top_srcdir)/po -o $@
