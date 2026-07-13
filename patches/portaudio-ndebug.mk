################################################################################
#
# portaudio
#
################################################################################

PORTAUDIO_VERSION = 190700_20210406
PORTAUDIO_SITE = http://files.portaudio.com/archives
PORTAUDIO_SOURCE = pa_stable_v$(PORTAUDIO_VERSION).tgz
PORTAUDIO_INSTALL_STAGING = YES
PORTAUDIO_MAKE = $(MAKE1)
PORTAUDIO_LICENSE = portaudio license (MIT-like plus special clause)
PORTAUDIO_LICENSE_FILES = LICENSE.txt

PORTAUDIO_DEPENDENCIES = \
	$(if $(BR2_PACKAGE_PORTAUDIO_ALSA),alsa-lib)

PORTAUDIO_CONF_OPTS = \
	$(if $(BR2_PACKAGE_PORTAUDIO_ALSA),--with-alsa,--without-alsa) \
	$(if $(BR2_PACKAGE_PORTAUDIO_OSS),--with-oss,--without-oss) \
	$(if $(BR2_PACKAGE_PORTAUDIO_CXX),--enable-cxx,--disable-cxx)

# Disable assertions for embedded ARM — PortAudio's assert(maxChans > 0)
# fires during ALSA device enumeration on strict embedded hardware (JP11/AKM DACs)
# where some plugin PCMs return 0 channels.
# The CFLAGS env var doesn't override Makefile CFLAGS, so we sed the Makefile.
define PORTAUDIO_ADD_NDEBUG
	$(SED) 's/^CFLAGS = /CFLAGS = -DNDEBUG /' $(@D)/Makefile
endef
PORTAUDIO_POST_CONFIGURE_HOOKS += PORTAUDIO_ADD_NDEBUG

$(eval $(autotools-package))
