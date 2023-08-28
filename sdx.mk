include $(TOPDIR)/owrt-qti-bsp/qtibsp.mk
include $(TOPDIR)/owrt-qti-bsp-prop/qtibspprop.mk
include $(TOPDIR)/owrt-qti-core/qticore.mk
include $(TOPDIR)/owrt-qti-core-prop/qticoreprop.mk
include $(TOPDIR)/owrt-qti-ss-mgr/qtissmgr.mk
include $(TOPDIR)/owrt-qti-ss-mgr-prop/qtissmgrprop.mk
include $(TOPDIR)/owrt-qti-location/qtilocation.mk
include $(TOPDIR)/owrt-qti-location-prop/qtilocationprop.mk
include $(TOPDIR)/owrt-qti-data/qtidata.mk
include $(TOPDIR)/owrt-qti-data-prop/qtidataprop.mk
include $(TOPDIR)/owrt-qti-ril-prop/qtirilprop.mk
include $(TOPDIR)/owrt-qti-bt/qtibt.mk
include $(TOPDIR)/owrt-qti-bt-prop/qtibtprop.mk
include $(TOPDIR)/owrt-qti-wlan/qtiwlan.mk
include $(TOPDIR)/owrt-qti-wlan-prop/qtiwlanprop.mk
include $(TOPDIR)/owrt-qti-audio/qtiaudio.mk
include $(TOPDIR)/owrt-qti-args/qtiargs.mk
include $(TOPDIR)/owrt-qti-pal/qtipal.mk
include $(TOPDIR)/owrt-qti-agm/qtiagm.mk
include $(TOPDIR)/owrt-qti-audio-prop/qtiaudioprop.mk
include $(TOPDIR)/owrt-qti-security/qtisecurity.mk
include $(TOPDIR)/owrt-qti-security-prop/qtisecurityprop.mk
include $(TOPDIR)/owrt-qti-ssdk/qtissdk.mk

# include mk files available only in internal builds
ifneq ($(EXTERNAL_BUILD),1)
	include $(TOPDIR)/owrt-qti-location-internal/qtilocationinternal.mk
	include $(TOPDIR)/owrt-qti-cta-internal/qtictainternal.mk
	include $(TOPDIR)/owrt-qti-internal/qtinternal.mk
	include $(TOPDIR)/owrt-qti-security-internal/qtisecurityinternal.mk
	include $(TOPDIR)/owrt-qti-data-internal/qtidatainternal.mk
	include $(TOPDIR)/owrt-qti-core-internal/qticoreinternal.mk
endif

OPENWRT_STANDARD:=luci openssl-util diag

UTILS:=file luci-app-samba rng-tools profilerd tcpdump ip-bridge conntrack conntrackd ethtool pciutils iw-full fping

COREBSP_UTILS:=pm-utils

ifeq ($(EXTERNAL_BUILD),1)
QTIBSPPROP += xmllib_prebuilt
endif
